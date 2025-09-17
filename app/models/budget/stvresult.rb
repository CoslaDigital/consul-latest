# In app/models/budget/stvresult.rb

class Budget
  class Stvresult
    attr_accessor :budget, :heading, :current_investment

    def initialize(budget, heading)
      @budget = budget
      @heading = heading
      @elected_investments = []
      @eliminated_investments = []
      @elimination_log = []
      @log_file_name = "stv_voting_#{budget.name}_#{heading.name}.log"
      log_path = Rails.root.join('log', @log_file_name)
      File.open(log_path, 'w') {}
    end

    def droop_quota(votes, seats)
      (votes / (seats + 1)).floor + 1
    end

    def calculate_stv_winners
      reset_winners

      # --- 1. Gather all election parameters at the start ---
      seats = budget.stv_winners
      votes_cast = budget.ballots.count
      candidates = @heading.investments.where(budget_id: @budget.id, selected: true)
      candidate_count = candidates.count
      quota = droop_quota(votes_cast, seats)
      investment_titles = candidates.pluck(:id, :title).to_h

      # --- 2. Write the introductory block ---
      write_to_output("<h1>STV Election Results</h1>")
      write_to_output("<h2>#{@budget.name} - #{@heading.name}</h2>")
      write_to_output("<hr>")
      write_to_output("<h3>🗳️ Election Summary</h3>")
      write_to_output("<ul>")
      write_to_output("  <li><strong>Seats to fill:</strong> #{seats}</li>")
      write_to_output("  <li><strong>Total Candidates:</strong> #{candidate_count}</li>")
      write_to_output("  <li><strong>Total Valid Votes Cast:</strong> #{votes_cast}</li>")
      write_to_output("</ul>")
      write_to_output("<h3>👥 Candidates</h3>")
      write_to_output("<p>The following #{candidate_count} candidates were on the ballot:</p>")
      write_to_output("<div style='column-count: 2; column-gap: 20px;'>")
      write_to_output("<ul>")
      investment_titles.values.sort.each do |title|
        write_to_output("<li>#{title}</li>")
      end
      write_to_output("</ul>")
      write_to_output("</div>")
      write_to_output("<h3>🎯 About the Quota</h3>")
      write_to_output("<p>The quota is the minimum number of votes a candidate needs to be guaranteed election. Once a candidate reaches this target, they are elected.</p>")
      write_to_output("<p>This election uses the <strong>Droop Quota</strong>, calculated with the formula below:</p>")
      write_to_output("<div style='background-color:#f0f0f0; padding: 10px; border-radius: 5px; margin: 10px 0; font-family: monospace;'>")
      write_to_output("  Quota = floor(Total Votes / (Seats + 1)) + 1<br>")
      write_to_output("  Quota = floor(#{votes_cast} / (#{seats} + 1)) + 1 = <strong>#{quota}</strong>")
      write_to_output("</div>")
      write_to_output("<hr>")

      # --- 3. Proceed with the calculation ---
      ballot_data = get_votes_data
      winners = calculate_results(ballot_data, seats, quota, investment_titles)

      update_winning_investments(winners)
      update_custom_page(@log_file_name)
      winners
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
      Budget::Investment.where(id: winning_investment_ids).update_all(winner: true)
    end

    def get_votes_data(ballots = get_ballots)
      votes_data = []
      ballots.each do |ballot|
        votes_data.concat(get_ballot_lines(ballot.id))
      end
      votes_data
    end

    def get_ballot_lines(ballot_id)
      ballot_lines = Budget::Ballot::Line.where(ballot_id: ballot_id)
      votes_data = []
      rankings = ballot_lines.pluck(:investment_id)
      votes_data << { rankings: rankings }
      votes_data
    end

    def update_custom_page(filename)
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