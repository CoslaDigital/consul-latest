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
      #@stv_logger = ActiveSupport::Logger.new(log_path)
      #@stv_logger.level = Logger::INFO
    end
    
    def droop_quota(votes, seats)
      (votes/(seats + 1)).floor + 1
    end  
    
    def calculate_stv_winners
  reset_winners

  # --- 1. Gather all election parameters at the start ---
  seats = budget.stv_winners
  votes_cast = budget.ballots.count
  candidates = @heading.investments.where(budget_id: @budget.id, selected: true)
  candidate_count = candidates.count
  quota = droop_quota(votes_cast, seats)
  
  # Create the title lookup hash here to pass to the next method
  investment_titles = candidates.pluck(:id, :title).to_h

  # --- 2. Write the new, detailed introductory block ---
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
  # Create a multi-column list for readability, especially with many candidates.
  write_to_output("<div style='column-count: 2; column-gap: 20px;'>")
  write_to_output("<ul>")
  # Sort the candidate names alphabetically
  investment_titles.values.sort.each do |title|
    write_to_output("<li>#{title}</li>")
  end
  write_to_output("</ul>")
  write_to_output("</div>")  
  write_to_output("<h3>🎯 About the Quota</h3>")
  write_to_output("<p>The quota is the minimum number of votes a candidate needs to be guaranteed election. Once a candidate reaches this target, they are elected.</p>")
  write_to_output("<p>This election uses the <strong>Droop Quota</strong>, calculated with the formula below:</p>")
  
  # A styled box to make the formula and calculation stand out
  write_to_output("<div style='background-color:#f0f0f0; padding: 10px; border-radius: 5px; margin: 10px 0; font-family: monospace;'>")
  write_to_output("  Quota = floor(Total Votes / (Seats + 1)) + 1<br>")
  write_to_output("  Quota = floor(#{votes_cast} / (#{seats} + 1)) + 1 = <strong>#{quota}</strong>")
  write_to_output("</div>")
  write_to_output("<hr>")


  # --- 3. Proceed with the calculation ---
  ballot_data = get_votes_data
  # Pass the investment_titles hash to the calculation method
  winners = calculate_results(ballot_data, seats, quota, investment_titles)
  
  update_winning_investments(winners)
  update_custom_page(@log_file_name)
  winners
end
        
    def get_ballots
    ballots = budget.ballots
    end
    
    def count_votes(ballots)
      ballots.each do |ballot|
        distribute_votes2(ballot.id)
     end
    end
  
    def calculate_results(votes_data, seats, quota, investment_titles)
      initial_vote_counts = Hash.new(0)
      initial_vote_counts = {}
      investment_titles.keys.each do |investment_id|
        # write_to_output( "setting up #{investment.id}")
        initial_vote_counts[investment_id] = 0
      end
      empty_seats = seats
      write_to_output( "About to get the data, Seats to fill: #{empty_seats}<br>")
      # Count the initial votes for each investment
      votes_data.each do |vote|
        if vote[:rankings].empty?
         #  write_to_output( "<p>Discarding invalid vote: #{vote}. Rankings are empty.</p>")
        else
          investment_id = vote[:rankings].first
          if initial_vote_counts.key?(investment_id)
            initial_vote_counts[investment_id] += 1
            # write_to_output( "Initial vote counted for investment #{investment_id}")
          else
            # Rails.logger.error "Invalid vote: Investment #{investment_id} does not exist.")
          end
       end
     end
     # Initialize elected and eliminated investments arrays
     @elected_investments = []
     @eliminated_investments = []
     iteration = 1
     loop do # START OF REPLACEMENT BLOCK
    write_to_output( "<br><h2>Round #{iteration}:</h2>")
    write_to_output( "<p>Quota to be elected: #{quota}</p>")

    # --- 1. DISPLAY CURRENT STANDINGS FIRST ---
    sorted_investments = initial_vote_counts.sort_by { |_, count| -count }
    if sorted_investments.empty?
      write_to_output( "<p>No more candidates to consider.</p><br>")
      break
    end

    write_to_output("<p><strong>Current Standings:</strong></p>")
    write_to_output("<table><thead><tr><th>Candidate</th><th>Votes</th></tr></thead><tbody>")
    
    sorted_investments.each do |investment_id, count|
      title = investment_titles[investment_id] || "Unknown Candidate"
      # Corrected the HTML row structure and rounded the vote count for fractional votes
      write_to_output("<tr><td>#{title} (#{investment_id})</td><td>#{count.round(2)}</td></tr>")
    end
    
    # IMPORTANT: Close the table here so the standings are a complete, separate section
    write_to_output("</tbody></table><br>")

    # --- 2. NOW, DECIDE WHETHER TO ELECT OR ELIMINATE ---
    elected = sorted_investments.select { |_, count| count >= quota }

    if elected.present?
      write_to_output("<strong>Action:</strong> A candidate has met or exceeded the quota.")
      elected.each do |investment_id, count|
        @elected_investments << investment_id
        title = investment_titles[investment_id]
        write_to_output( "<br><strong>Elected: #{title} (#{investment_id})</strong> (has #{count.round(2)} votes)<br>")

        surplus = count - quota
        if surplus > 0
          write_to_output( "<p>Transferring #{surplus.round(2)} surplus votes...</p>")
          # ... (rest of surplus logic is the same) ...
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
      @elimination_log << { round: iteration, title: eliminated_title, id: eliminated_id, votes: eliminated_votes }
      write_to_output( "<br><strong>Eliminated: #{eliminated_title} (#{eliminated_id})</strong><br>")
      @eliminated_investments << eliminated_id
      initial_vote_counts.delete(eliminated_id)

      reallocated_votes = transfer_eliminated_votes(votes_data, eliminated_id)
      unless reallocated_votes.empty?
        write_to_output( "<p>Reallocating #{reallocated_votes.size} votes from #{eliminated_title}...</p>")
        reallocated_votes.each do |id|
          if initial_vote_counts.key?(id)
            initial_vote_counts[id] += 1
          end
        end
      end
      
      break if empty_seats <= 0
    end

    # --- 3. END OF ROUND SUMMARY ---
    write_to_output( "<hr><p><strong>End of Round #{iteration} Summary</strong></p>")
    unless @elected_investments.empty?
      elected_names = @elected_investments.map { |id| investment_titles[id] }.join(', ')
      write_to_output( "<p>Elected so far: #{elected_names}</p>")
    end
    write_to_output( "<p>Remaining seats to fill: #{empty_seats}</p><br>")

    iteration += 1
  end # END OF REPLACEMENT BLOCK  
  # Close the table from the final round of counting
  write_to_output("</tbody></table>") 
  write_to_output("<hr>") # Add a dividing line
  
  # Create the final results announcement
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
    write_to_output("</ul>")
  else
    write_to_output("<p>No candidates were elected in this process.</p>")
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
  
   write_to_output( "<p>Reallocating votes for #{eliminated_investment_id}</p>")
  votes_data.each do |vote|
    if vote[:rankings].first == eliminated_investment_id
       next_preference_index = 1
      loop do
        next_preference = vote[:rankings][next_preference_index]
        
        if next_preference && next_preference != eliminated_investment_id && !elected_or_eliminated?(next_preference)
          reallocated_votes << next_preference.to_i
          break
        elsif next_preference.nil? || next_preference == eliminated_investment_id
          exhausted_ballot_count += 1
          break
        end

        next_preference_index += 1
      end
      vote[:rankings].shift  # Remove the eliminated investment from the first preference
    end
  end
  if exhausted_ballot_count > 0
    write_to_output("<p><em>(#{exhausted_ballot_count} votes could not be transferred as they had no further valid preferences.)</em></p>")
  end
  reallocated_votes
end

  
def elected_or_eliminated?(investment_id)
  if @elected_investments.include?(investment_id)
    return true
  elsif @eliminated_investments.include?(investment_id)
    return true
  else
    return false
  end
end 

def transfer_surplus_votes(votes_data, elected_investment_id )
  surplus_contributing_ballots = []
  write_to_output( "<p>elected id is #{elected_investment_id}</p>")

  # Transfer surplus votes proportionally to next preferences
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

 
    def transfer_surplus_votes_old(votes_data, elected_investment_id, surplus)
  # Calculate the number of votes that contributed to the surplus
  surplus_contributing_votes = votes_data.count { |vote| vote[:rankings].first == elected_investment_id }
  transfer_ratio = surplus.to_f / surplus_contributing_votes
  write_to_output( "<p>transfer ratio is #{transfer_ratio}</p>")

  # Transfer surplus votes proportionally to next preferences
  votes_data.each do |vote|
    if vote[:rankings].first == elected_investment_id
      vote[:rankings].shift  # Remove the elected investment from the first preference

      # Transfer surplus votes proportionally to next preferences
      vote[:rankings].each_with_index do |investment_id, index|
        if index > 0
          write_to_output( "checking the transfer - adding #{transfer_ratio} to #{vote[:rankings][index]}")
          vote[:rankings][index] += transfer_ratio  # Increase next preference votes by transfer_ratio
        end
      end

      vote[:rankings].compact!  # Remove nil values
    end
  end
end

    

    def update_winning_investments(winning_investment_ids)
      Budget::Investment.where(id: winning_investment_ids).update_all(winner: true)
    end
    
    def distribute_votes(ballot)
      ballot.each do |preference|
        candidate = @candidates.find { |c| c.name == preference }
        if candidate && !candidate.elected
          candidate.receive_votes(1)
          break
        end
      end
    end

    def get_votes_data ballots = get_ballots 
      votes_data = [] 
      ballots.each do |ballot|
        # write_to_output( "Votes data #{votes_data}"
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
    # Check if the file exists
    if File.exist?(file_path)
    # Read the contents of the file
      file_content = File.read(file_path)
      html_content = parse_log_to_html(file_content)
      # Extract the file name without extension to use as slug and title
      file_name = File.basename(file_path, '.*')
      page = SiteCustomization::Page.find_or_initialize_by(slug: file_name.downcase.tr(' ', '-'))
      status =  'published' 
      title = file_name
      content = html_content
      if  page.update(status: 'published', updated_at: Time.now, title: file_name, content: html_content)
        Rails.logger.info "New page '#{file_name}' created successfully with content from '#{file_path}'"
      else
        Rails.logger.info "Failed to create new page with content from '#{file_path}' due to errors:"
        Rails.logger.info new_page.errors.full_messages.join(", ")
      end
    else
      puts "File '#{file_path}' does not exist."
    end
  end
     
    def candidates
      heading.investments.selected.sort_by_votes
    end

    def candidates_ids
     heading.investments.selected.pluck(:id)
    end
    
    def investments
      heading.investments.selected.sort_by_ballots
    end

    def inside_budget?
      available_budget >= @current_investment.price
    end

    def available_budget
      total_budget - money_spent
    end

    def total_budget
      heading.price
    end

    def money_spent
      @money_spent ||= 0
    end
    
    def reset_winners
      candidates.update_all(winner: false)
      candidates.update_all(incompatible: false)
      candidates.update_all(votes: 0)
    end


    def set_winner
      @money_spent += @current_investment.price
      @current_investment.update!(winner: true)
    end
    

    def winners
      investments.where(winner: true)
    end
    
    def get_elected_candidates
    @candidates.select { |candidate| candidate.winner }
    end
    
    def parse_log_to_html(log_content)
      log_content.gsub("\n", "<br>")
      log_content.gsub("#", "")
    end
    private

    def write_to_output(message)
      log_path = Rails.root.join('log', @log_file_name)
      File.open(log_path, 'a') { |file| file.puts(message) }
    end
  end
end