# In app/models/budget/stvresult.rb

class Budget
  class Stvresult
    attr_accessor :budget, :heading, :current_investment

    def initialize(budget, heading, user:)
      @budget = budget
      @heading = heading
      @elected_investments = []
      @eliminated_investments = []
      @elimination_log = []
      @log_file_name = "stv_voting_#{budget.name}_#{heading.name}.log"
      @user = user
      log_path = Rails.root.join('log', @log_file_name)
      File.open(log_path, 'w') {}
    end

    def droop_quota(votes, seats)
      (votes / (seats + 1)).floor + 1
    end

    def calculate_stv_winners
      # ----------------------------------------------------------------
      # Gather all the initial data for the election.
      # ----------------------------------------------------------------
      reset_winners

      summary_slug = "stv_results_#{@budget.name}_#{@heading.name}".downcase.tr(' ', '-')
      detail_slug  = "stv_details_#{@budget.name}_#{@heading.name}".downcase.tr(' ', '-')
      summary_title = "Election Results: #{@budget.name}"
      detail_title  = "Detailed Election Log: #{@budget.name}"

      seats = budget.stv_winners
      votes_cast = budget.ballots.count
      candidates = @heading.investments.where(budget_id: @budget.id, selected: true)
      quota = droop_quota(votes_cast, seats)
      investment_titles = candidates.pluck(:id, :title).to_h
      ballot_data = get_votes_data
      dynamic_quota_enabled = @budget.stv_dynamic_quota?
      calculator = ::StvCalculator.new
      result = calculator.calculate(ballot_data, seats, quota, investment_titles, dynamic_quota_enabled: dynamic_quota_enabled)
      # Render the summary report using the new component
      summary_html_report = ApplicationController.render(
      StvSummaryReportComponent.new(
        result: result,
        budget: @budget,
        heading: @heading,
        candidates: candidates,
        votes_cast: votes_cast,
        quota: quota,
        report_title: summary_title,
        detail_page_slug: detail_slug,
        dynamic_quota_enabled: dynamic_quota_enabled
      ),
      layout: false
      )


      # Render the final HTML report using the ViewComponent
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
    assigns: { # Pass all necessary instance variables to the template
      budget: @budget,
      heading: @heading,
      result: result,
      candidates: candidates,
      votes_cast: votes_cast,
      quota: quota,
      investment_titles: investment_titles
    }
  )

  # --- Generate the PDF and attach it to the budget ---
  pdf_file = WickedPdf.new.pdf_from_string(pdf_html_content)
  
  # Define a heading-specific title for the document
  document_title = "STV Full Report: #{@heading.name}"
  
  # First, remove any old report to avoid duplicates
  @heading.documents.where(title: document_title).destroy_all
  
  # Attach the new one using your Documentable concern
  @heading.documents.create!(
    title: "STV Full Report: #{@heading.name}",
    user: @user,
    attachment: {
      io: StringIO.new(pdf_file), # Treat the in-memory PDF string as a file
      filename: "stv_report_#{@budget.slug}_#{@heading.slug}.pdf",
      content_type: "application/pdf"
    }
  )

      # Update the database with the final results
      update_winning_investments(result.winners)
      update_custom_page(summary_html_report, summary_title, summary_slug)
      update_custom_page(detailed_html_report, detail_title, detail_slug)

      # Return the array of winner IDs.
      result.winners
    end
    
        
    def get_ballots
      budget.ballots
    end

    def count_votes(ballots)
      ballots.each do |ballot|
        distribute_votes2(ballot.id)
      end
    end

    def calculate_results(votes_data, seats, quota, investment_titles)
      initial_vote_counts = {}
      investment_titles.keys.each do |investment_id|
        initial_vote_counts[investment_id] = 0
      end

      # Count the initial votes for each investment
      votes_data.each do |vote|
        next if vote[:rankings].empty?
        investment_id = vote[:rankings].first
        if initial_vote_counts.key?(investment_id)
          initial_vote_counts[investment_id] += 1
        end
      end

      @elected_investments = []
      @eliminated_investments = []
      empty_seats = seats
      iteration = 1

      loop do
        write_to_output("<br><h2>Round #{iteration}:</h2>")
        write_to_output("<p>Quota to be elected: #{quota}</p>")

        sorted_investments = initial_vote_counts.sort_by { |_, count| -count }
        if sorted_investments.empty?
          write_to_output("<p>No more candidates to consider.</p><br>")
          break
        end

        write_to_output("<p><strong>Current Standings:</strong></p>")
        write_to_output("<table><thead><tr><th>Candidate</th><th>Votes</th></tr></thead><tbody>")
        sorted_investments.each do |investment_id, count|
          title = investment_titles[investment_id] || "Unknown Candidate"
          write_to_output("<tr><td>#{title} (#{investment_id})</td><td>#{count.round(2)}</td></tr>")
        end
        write_to_output("</tbody></table><br>")

        elected = sorted_investments.select { |_, count| count >= quota }

        if elected.present?
          write_to_output("<strong>Action:</strong> A candidate has met or exceeded the quota.")
          elected.each do |investment_id, count|
            @elected_investments << investment_id
            title = investment_titles[investment_id]
            write_to_output("<br><strong>Elected: #{title} (#{investment_id})</strong> (has #{count.round(2)} votes)<br>")
            surplus = count - quota
            if surplus > 0
              write_to_output("<p>Transferring #{surplus.round(2)} surplus votes...</p>")
              reallocated_votes = transfer_surplus_votes(votes_data, investment_id)
              if reallocated_votes.any?
                ratio = surplus.to_f / reallocated_votes.size
                reallocated_votes.each do |id|
                  if initial_vote_counts.key?(id)
                    initial_vote_counts[id] += ratio
                  end
                end
              end
            end
            empty_seats -= 1
            initial_vote_counts.delete(investment_id)
            break if empty_seats <= 0
          end
        else
          write_to_output("<strong>Action:</strong> No candidate met the quota. Eliminating the candidate with the fewest votes.")

          eliminated_investment = sorted_investments.last
          eliminated_id = eliminated_investment[0]
          eliminated_title = investment_titles[eliminated_id] || "Unknown Candidate"
          eliminated_votes = eliminated_investment[1]

          @elimination_log << { round: iteration, title: eliminated_title, id: eliminated_id, votes: eliminated_votes }

          write_to_output("<br><strong>Eliminated: #{eliminated_title} (#{eliminated_id})</strong><br>")
          @eliminated_investments << eliminated_id
          initial_vote_counts.delete(eliminated_id)

          reallocated_votes = transfer_eliminated_votes(votes_data, eliminated_id)
          unless reallocated_votes.empty?
            write_to_output("<p>Reallocating #{reallocated_votes.size} votes from #{eliminated_title}...</p>")
            reallocated_votes.each do |id|
              if initial_vote_counts.key?(id)
                initial_vote_counts[id] += 1
              end
            end
          end
          break if empty_seats <= 0
        end

        write_to_output("<hr><p><strong>End of Round #{iteration} Summary</strong></p>")
        unless @elected_investments.empty?
          elected_names = @elected_investments.map { |id| investment_titles[id] }.join(', ')
          write_to_output("<p>Elected so far: #{elected_names}</p>")
        end
        write_to_output("<p>Remaining seats to fill: #{empty_seats}</p><br>")

        iteration += 1
      end

      # --- FINAL RESULTS SUMMARY ---
      write_to_output("<hr>")
      write_to_output("<h2>✅ Election Complete: Final Results</h2>")

      if @elected_investments.any?
        winner_count = @elected_investments.size
        candidate_word = (winner_count == 1) ? "candidate has" : "candidates have"
        write_to_output("<p>The following <strong>#{winner_count}</strong> #{candidate_word} been elected:</p>")
        write_to_output("<ul>")
        @elected_investments.each do |winner_id|
          winner_title = investment_titles[winner_id] || "Unknown Candidate"
          write_to_output("<li><strong>#{winner_title}</strong> (ID: #{winner_id})</li>")
        end
        write_to_output("</ul>")
      else
        write_to_output("<p>No candidates were elected in this process.</p>")
      end

      if @elimination_log.any?
        write_to_output("<h3>📊 Order of Elimination</h3>")
        write_to_output("<table><thead><tr><th>Round</th><th>Candidate Eliminated</th><th>Votes at Elimination</th></tr></thead><tbody>")
        @elimination_log.each do |log_entry|
          write_to_output("<tr>")
          write_to_output("  <td>#{log_entry[:round]}</td>")
          write_to_output("  <td>#{log_entry[:title]} (#{log_entry[:id]})</td>")
          write_to_output("  <td>#{log_entry[:votes].round(2)}</td>")
          write_to_output("</tr>")
        end
        write_to_output("</tbody></table>")
      end

      if @elected_investments.size < seats
        unfilled_seats = seats - @elected_investments.size
        write_to_output("<p><strong>Notice:</strong> #{unfilled_seats} seat(s) could not be filled because there were no more candidates with enough transferable votes to reach the quota.</p>")
      end

      @elected_investments
    end

    def transfer_eliminated_votes(votes_data, eliminated_investment_id)
      reallocated_votes = []
      exhausted_ballot_count = 0

      votes_data.each do |vote|
        if vote[:rankings].first == eliminated_investment_id
          next_preference_index = 1
          loop do
            next_preference = vote[:rankings][next_preference_index]
            if next_preference && !elected_or_eliminated?(next_preference)
              reallocated_votes << next_preference
              break
            elsif next_preference.nil?
              exhausted_ballot_count += 1
              break
            end
            next_preference_index += 1
          end
          vote[:rankings].shift
        end
      end

      if exhausted_ballot_count > 0
        write_to_output("<p><em>(#{exhausted_ballot_count} votes could not be transferred as they had no further valid preferences.)</em></p>")
      end
      reallocated_votes
    end

    def elected_or_eliminated?(investment_id)
      @elected_investments.include?(investment_id) || @eliminated_investments.include?(investment_id)
    end

    def transfer_surplus_votes(votes_data, elected_investment_id)
      surplus_contributing_ballots = []
      votes_data.each do |vote|
        if vote[:rankings].first == elected_investment_id
          next_preference = vote[:rankings][1]
          if next_preference
            surplus_contributing_ballots << next_preference
          end
        end
      end
      surplus_contributing_ballots
    end
    
    def update_winning_investments(winning_investment_ids)
  ids = winning_investment_ids.to_a
  Rails.logger.info "--- [DEBUG] STARTING update_winning_investments for IDs: #{ids.inspect} ---"
  return if ids.empty?

  investments = Budget::Investment.unscoped.where(id: ids)

  investments.each do |investment|
    Rails.logger.info "--- [DEBUG] About to set winner=true for Investment ##{investment.id} ---"
    
    investment.class.without_auditing do
      investment.update!(winner: true)
    end
    
    # Check the flag immediately after updating
    investment.reload
    Rails.logger.info "--- [DEBUG] FINISHED update for Investment ##{investment.id}. Current winner status: #{investment.winner} ---"
  end
  
  Rails.logger.info "--- [DEBUG] FINISHED update_winning_investments. ---"
end

    
    
    def oldupdate_winning_investments(winning_investment_ids)
      Budget::Investment.where(id: winning_investment_ids).update_all(winner: true)
    end

    def get_votes_data(ballots = get_ballots)
  # Get all the ballot IDs for the current budget in one query
  ballot_ids = ballots.pluck(:id)
  
  # Get all the lines for ALL those ballots in a single query
  all_lines = Budget::Ballot::Line.where(ballot_id: ballot_ids)
                                  .select(:ballot_id, :investment_id)
  
  # Group the lines by their ballot_id in memory (very fast)
  lines_by_ballot = all_lines.group_by(&:ballot_id)
  
  # Transform the grouped data into the required array of hashes format,
  # preserving the original order of ballots.
  ballot_ids.map do |id|
    # Find the lines for the current ballot id, convert them to an array of investment_ids,
    # or return an empty array if the ballot had no lines.
    rankings = lines_by_ballot[id]&.map(&:investment_id) || []
    { rankings: rankings }
  end
end

    def old_get_votes_data(ballots = get_ballots)
      votes_data = []
      ballots.each do |ballot|
        votes_data.concat(get_ballot_lines(ballot.id))
      end
      votes_data
    end

    def old_get_ballot_lines(ballot_id)
      ballot_lines = Budget::Ballot::Line.where(ballot_id: ballot_id)
      votes_data = []
      rankings = ballot_lines.pluck(:investment_id)
      votes_data << { rankings: rankings }
      votes_data
    end


    def update_custom_page(html_content, page_title, page_slug)
      file_name_for_slug = "stv_voting_#{@budget.name}_#{@heading.name}"
      slug = file_name_for_slug.downcase.tr(' ', '-')
  
      page = SiteCustomization::Page.find_or_initialize_by(slug: page_slug)

      if page.update(status: 'published', title: page_title, content: html_content)
       Rails.logger.info "Page '#{page_title}' updated successfully."
      else
       Rails.logger.error "Failed to update page '#{page_title}': #{page.errors.full_messages.join(", ")}"
     end
   end

    def old_update_custom_page(filename, page_title)
      file_path = Rails.root.join('log', filename)
      if File.exist?(file_path)
        file_content = File.read(file_path)
        html_content = parse_log_to_html(file_content)
        file_name = File.basename(file_path, '.*')
        page = SiteCustomization::Page.find_or_initialize_by(slug: file_name.downcase.tr(' ', '-'))
        if page.update(status: 'published', updated_at: Time.now, title: file_name, content: html_content)
          Rails.logger.info "Page '#{file_name}' updated successfully."
        else
          Rails.logger.error "Failed to update page '#{file_name}': #{page.errors.full_messages.join(", ")}"
        end
      else
        puts "Log file '#{file_path}' does not exist."
      end
    end

    def candidates
      heading.investments.selected.sort_by_votes
    end

    def reset_winners
      candidates.update_all(winner: false, votes: 0)
    end

    def parse_log_to_html(log_content)
      log_content.gsub!("\n", "<br>")
      log_content.gsub!("#", "")
      log_content
    end

    private

    def write_to_output(message)
      log_path = Rails.root.join('log', @log_file_name)
      File.open(log_path, 'a') { |file| file.puts(message) }
    end
  end
end