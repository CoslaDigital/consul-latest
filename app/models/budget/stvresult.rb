# In app/models/budget/stvresult.rb

class Budget
  class Stvresult
    attr_accessor :budget, :heading, :current_investment

    StvEngineResult = Struct.new(:winners, :rounds, :unfilled_seats, :elimination_log)

    def initialize(budget, heading, user:)
      @budget = budget
      @heading = heading
      @elected_investments = []
      @eliminated_investments = []
      @elimination_log = []
      @rounds_data = []
      @exhausted_total = 0.0
      @log_file_name = "stv_voting_#{budget.name}_#{heading.name}.log"
      @user = user

      log_path = Rails.root.join('log', @log_file_name)
      File.open(log_path, 'w') {}
    end

    def droop_quota(total_value, seats)
      (total_value / (seats + 1)).floor + 1
    end

    def calculate_stv_winners
      reset_winners

      summary_slug = "stv_results_#{@budget.name}_#{@heading.name}".parameterize
      detail_slug = "stv_details_#{@budget.name}_#{@heading.name}".parameterize
      summary_title = "Election Results: #{@budget.name}"
      detail_title  = "Detailed Election Log: #{@budget.name}"

      seats = @heading.max_winners
      candidates = @heading.investments.where(budget_id: @budget.id, selected: true)
      investment_titles = candidates.pluck(:id, :title).to_h

      ballot_data = get_votes_data
      votes_cast = ballot_data.size

      if seats <= 0 || votes_cast == 0 || candidates.empty?
        write_to_output("<h2>Election Aborted</h2><p>Missing seats, ballots, or candidates.</p>")
        return []
      end

      initial_quota = droop_quota(votes_cast.to_f, seats)
      dynamic_quota_enabled = @budget.stv_dynamic_quota?

      result = run_stv_wigm(ballot_data, seats, initial_quota, investment_titles, dynamic_quota_enabled)

      summary_html_report = ApplicationController.render(
        StvSummaryReportComponent.new(
          result: result,
          budget: @budget,
          heading: @heading,
          candidates: candidates,
          votes_cast: votes_cast,
          quota: initial_quota,
          report_title: summary_title,
          detail_page_slug: detail_slug,
          dynamic_quota_enabled: dynamic_quota_enabled
        ),
        layout: false
      )

      detailed_html_report = ApplicationController.render(
        StvDetailReportComponent.new(
          rounds: result.rounds,
          investment_titles: investment_titles,
          dynamic_quota_enabled: dynamic_quota_enabled
        ),
        layout: false
      )

      pdf_html_content = ApplicationController.render(
        template: "budgets/results/stv_report_pdf",
        layout: "pdf",
        assigns: {
          budget: @budget,
          heading: @heading,
          result: result,
          candidates: candidates,
          votes_cast: votes_cast,
          quota: initial_quota,
          investment_titles: investment_titles
        }
      )

      pdf_file = WickedPdf.new.pdf_from_string(pdf_html_content)
      document_title = "STV Full Report: #{@heading.name}"

      @heading.documents.where(title: document_title).destroy_all

      @heading.documents.create!(
        title: "STV Full Report: #{@heading.name}",
        user: @user,
        attachment: {
          io: StringIO.new(pdf_file),
          filename: "stv_report_#{@budget.slug}_#{@heading.slug}.pdf",
          content_type: "application/pdf"
        }
      )

      update_winning_investments(result.winners)
      update_custom_page(summary_html_report, summary_title, summary_slug)
      update_custom_page(detailed_html_report, detail_title, detail_slug)

      result.winners
    end

    private

      def run_stv_wigm(raw_votes_data, seats, current_quota, investment_titles, dynamic_quota_enabled)
        @elected_investments = []
        @eliminated_investments = []
        @elimination_log = []
        @rounds_data = []
        @exhausted_total = 0.0

        empty_seats = seats
        iteration = 1

        stateful_ballots = raw_votes_data.map do |vote|
          {
            rankings: vote[:rankings].dup,
            current_value: 1.0,
            current_candidate: vote[:rankings].first,
            exhausted: false
          }
        end

        active_candidates = investment_titles.keys
        sorted_standings = []

        loop do
          if dynamic_quota_enabled && iteration > 1
            total_active_value = stateful_ballots.sum { |b| b[:exhausted] ? 0 : b[:current_value] }
            current_quota = droop_quota(total_active_value, seats)
          end

          write_to_output("<br><h2>Round #{iteration}:</h2>")
          write_to_output("<p>Quota to be elected: #{current_quota}</p>")

          candidate_totals = Hash.new(0.0)
          active_candidates.each { |id| candidate_totals[id] = 0.0 }

          stateful_ballots.each do |ballot|
            next if ballot[:exhausted]

            # CRITICAL FIX: Only count votes if the candidate is still actively in the race!
            # This prevents candidates with a zero-surplus from being resurrected in the next round.
            if active_candidates.include?(ballot[:current_candidate])
              candidate_totals[ballot[:current_candidate]] += ballot[:current_value]
            end
          end

          sorted_standings = sort_standings_statutory(candidate_totals)

          round_info = {
            iteration: iteration,
            number: iteration,
            quota: current_quota,
            standings: sorted_standings.to_h,
            action: {},
            transfers: {}
          }

          write_to_output("<p><strong>Current Standings:</strong></p>")
          write_to_output("<table><thead><tr><th>Candidate</th><th>Votes</th></tr></thead><tbody>")
          sorted_standings.each do |investment_id, total|
            write_to_output("<tr><td>#{investment_titles[investment_id]} (#{investment_id})</td><td>#{total.round(5)}</td></tr>")
          end
          write_to_output("</tbody></table>")
          write_to_output("<p><em>Total Exhausted (Non-transferable) Votes: #{@exhausted_total.round(5)}</em></p><br>")

          candidates_over_quota = sorted_standings.select { |_, total| total >= current_quota }

          if candidates_over_quota.any?
            elected_id, elected_total = candidates_over_quota.first
            title = investment_titles[elected_id]
            surplus = elected_total - current_quota

            write_to_output("<strong>Action:</strong> #{title} is Elected with #{elected_total.round(5)} votes.")

            round_info[:action] = {
              type: :election,
              candidate_id: elected_id,
              title: title,
              count: elected_total,
              surplus: surplus
            }

            round_info[:transfers] = { type: :surplus, candidate_id: elected_id, amount: surplus }

            @elected_investments << elected_id
            active_candidates.delete(elected_id)
            empty_seats -= 1

            if surplus > 0 && empty_seats > 0
              transfer_fraction = surplus.to_f / elected_total
              write_to_output("<p>Transferring surplus of #{surplus.round(5)}. Transfer Value: #{transfer_fraction.round(5)} per ballot.</p>")

              ballots_to_transfer = stateful_ballots.select { |b| b[:current_candidate] == elected_id && !b[:exhausted] }
              ballots_to_transfer.each do |ballot|
                ballot[:current_value] *= transfer_fraction
                advance_ballot(ballot)
              end
            end
          else
            eliminated_id, eliminated_total = sorted_standings.last
            title = investment_titles[eliminated_id]

            write_to_output("<strong>Action:</strong> No one met quota. Eliminating #{title} with #{eliminated_total.round(5)} votes.")

            round_info[:action] = {
              type: :elimination,
              candidate_id: eliminated_id,
              title: title,
              count: eliminated_total
            }

            round_info[:transfers] = { type: :elimination, candidate_id: eliminated_id, amount: eliminated_total }

            @elimination_log << { round: iteration, title: title, id: eliminated_id, votes: eliminated_total }
            @eliminated_investments << eliminated_id
            active_candidates.delete(eliminated_id)

            ballots_to_transfer = stateful_ballots.select { |b| b[:current_candidate] == eliminated_id && !b[:exhausted] }
            ballots_to_transfer.each do |ballot|
              advance_ballot(ballot)
            end
          end

          @rounds_data << round_info

          break if empty_seats <= 0
          break if active_candidates.size <= empty_seats

          iteration += 1
        end

        if empty_seats > 0 && active_candidates.any?
          active_candidates.each do |id|
            @elected_investments << id
            title = investment_titles[id]
            write_to_output("<p><strong>#{title} elected automatically to fill remaining seat.</strong></p>")

            @rounds_data << {
              iteration: iteration,
              number: iteration,
              quota: current_quota,
              standings: sorted_standings.to_h,
              action: {
                type: :auto_election,
                candidate_id: id,
                title: title,
                count: 0
              },
              transfers: {}
            }
            iteration += 1
          end
        end

        write_to_output("<hr><h2>✅ Election Complete: Final Results</h2>")
        write_to_output("<p><strong>Final Statutory Exhausted Votes:</strong> #{@exhausted_total.round(5)}</p>")

        unfilled = seats - @elected_investments.size
        StvEngineResult.new(@elected_investments, @rounds_data, unfilled, @elimination_log)
      end

      def sort_standings_statutory(candidate_totals)
        candidate_totals.to_a.sort do |(id_a, total_a), (id_b, total_b)|
          cmp = total_b <=> total_a

          if cmp == 0
            (@rounds_data.size - 1).downto(0) do |i|
              history_a = @rounds_data[i][:standings][id_a] || 0.0
              history_b = @rounds_data[i][:standings][id_b] || 0.0
              cmp = history_b <=> history_a
              break if cmp != 0
            end
          end

          if cmp == 0
            seed_a = "#{@budget.id}-#{@heading.id}-#{id_a}".hash
            seed_b = "#{@budget.id}-#{@heading.id}-#{id_b}".hash

            lottery_a = Random.new(seed_a).rand
            lottery_b = Random.new(seed_b).rand

            cmp = lottery_b <=> lottery_a

            cmp = id_a <=> id_b if cmp == 0
          end

          cmp
        end
      end

      def advance_ballot(ballot)
        elected_or_eliminated = @elected_investments + @eliminated_investments
        next_active_preference = ballot[:rankings].find { |c_id| !elected_or_eliminated.include?(c_id) }

        if next_active_preference
          ballot[:current_candidate] = next_active_preference
        else
          ballot[:exhausted] = true
          ballot[:current_candidate] = nil
          @exhausted_total += ballot[:current_value]
        end
      end

      def get_ballots
        budget.ballots
      end

      def get_votes_data(ballots = get_ballots)
        ballot_ids = ballots.pluck(:id)

        all_lines = Budget::Ballot::Line.where(ballot_id: ballot_ids, heading_id: @heading.id)
                                        .order(:position)
                                        .select(:ballot_id, :investment_id)

        lines_by_ballot = all_lines.group_by(&:ballot_id)

        valid_ballots = []
        ballot_ids.each do |id|
          rankings = lines_by_ballot[id]&.map(&:investment_id) || []
          valid_ballots << { rankings: rankings } if rankings.any?
        end

        valid_ballots
      end

      def update_winning_investments(winning_investment_ids)
        ids = winning_investment_ids.to_a
        return if ids.empty?
        investments = Budget::Investment.unscoped.where(id: ids)
        investments.each do |investment|
          investment.class.without_auditing { investment.update!(winner: true) }
          investment.reload
        end
      end

      def update_custom_page(html_content, page_title, page_slug)
        page = SiteCustomization::Page.find_or_initialize_by(slug: page_slug)
        page.update(status: 'published', title: page_title, content: html_content)
      end

      def candidates
        heading.investments.selected.sort_by_votes
      end

      def reset_winners
        candidates.update_all(winner: false, votes: 0)
      end

      def write_to_output(message)
        log_path = Rails.root.join('log', @log_file_name)
        File.open(log_path, 'a') { |file| file.puts(message) }
      end
  end
end
