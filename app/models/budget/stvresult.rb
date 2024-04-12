class Budget
  class Stvresult
    attr_accessor :budget, :heading, :current_investment
    
    def initialize(budget, heading)
      @budget = budget
      @heading = heading
      @elected_investments = []
      @eliminated_investments = []
      @log_file_name = "stv_budget_#{budget.id}_heading_#{heading.id}.log"
      log_path = Rails.root.join('log', @log_file_name)
      File.open(log_path, 'w') {}
      #@stv_logger = ActiveSupport::Logger.new(log_path)
      #@stv_logger.level = Logger::INFO
    end
    
    def droop_quota(votes, seats)
      write_to_output( "<h2>Votes = #{votes}, Seats = #{seats}</h2>")
      (votes/(seats + 1)).floor + 1
    end  
    
    def calculate_stv_winners
      reset_winners
      seats = budget.stv_winners
      votes = budget.ballots.count
      quota = droop_quota(votes, seats) # Calculate the Droop quota once
      write_to_output( "<p><h3>the quota is #{quota}</h3></p>")
      ballots = get_ballots
      ballot_data = get_votes_data
      write_to_output( "<p>About to count votes</p>")
      winners = calculate_results(ballot_data, seats, quota)
      write_to_output( "<br><p>Election Complete</p>")
      write_to_output( "<p>Results are #{winners}</p>")
      update_winning_investments(winners)
      Rails.logger.info("startingto create custom page")
      update_custom_page(@log_file_name)
      Rails.logger.info("finished creating custom page")
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
  
    def calculate_results(votes_data, seats, quota)
      initial_vote_counts = Hash.new(0)
      # Fetch all investments
      investments = @heading.investments.where(budget_id: @budget.id, selected: true)
      initial_vote_counts = {}
      investments.each do |investment|
        # write_to_output( "setting up #{investment.id}")
        initial_vote_counts[investment.id] = 0
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
     loop do
       write_to_output( "<br><h2>Round #{iteration}:</h2><br>")
       write_to_output( "<p>----------------</p><br>")
#    write_to_output( "Quota is #{quota}<br>")

    # Sort investments by their initial vote counts
    sorted_investments = initial_vote_counts.sort_by { |investment_id, count| -count }
    if sorted_investments.empty?
     write_to_output( "<p>No more candidates to consider.</p><br>")
     break
    end
    # Output sorted investments to Rails logger
    write_to_output("<p>Remaining Candidates in order of votes:</p>")
       sorted_investments.each do |investment_id, count|
       write_to_output("<p>Investment ID: #{investment_id}, Vote Count: #{count}</p><br>")
       investments.find_by(id: investment_id)&.update(votes: count)
    end
    # Check if there are any investments with enough votes to meet the quota
    elected = sorted_investments.select { |investment_id, count| count >= quota }
    # Log information about elected investments
    #elected.each do |investment_id, count|
    # write_to_output( "<p><strong>Elected: Investment #{investment_id} (votes count: #{count})</strong></p><br>"
    #end
    if elected.present?
    elected.each do |investment_id, count|
      # Add the elected investment to the list of elected investments
      @elected_investments << investment_id
      write_to_output( "<br><strong>Elected: Investment #{investment_id} (votes count: #{count}: exceeds quota)</strong><br>")

      # Calculate surplus votes and transfer them to next preferences
      surplus = count - quota
      write_to_output( "<p>surplus is #{surplus}</p>")
      if surplus > 0
      reallocated_votes = transfer_surplus_votes(votes_data, investment_id)
      ratio = surplus.to_f/reallocated_votes.size
      write_to_output( "<p>#{reallocated_votes.size} ratio is #{ratio}</p>")
      reallocated_votes.each do |id|
      if initial_vote_counts.key?(id)
         # Increment the vote count for the investment ID
           initial_vote_counts[id] += ratio
           write_to_output( "<p>Reallocated vote to investment #{id}</p><br>")
      else
         # Optionally, handle the case where the investment ID is not found in the hash
          Rails.logger.warn "Investment ID #{id} not found in initial vote counts"
       end
      end
      end
      # Reduce the number of seats left to fill

      empty_seats -= 1
      write_to_output( "<p>Remaining empty seats <strong> #{empty_seats}</strong><br>")
      # Remove the elected investment from consideration
      initial_vote_counts.delete(investment_id)
      # Break if no more seats left to fill
      break if empty_seats <= 0
      end
    else
      write_to_output( "<p> No investments meet the quota, so eliminate the lowest-ranking investment</p>")
      eliminated_investment = sorted_investments.last
      write_to_output( "<p>Candidate to be eliminated<strong> #{eliminated_investment}</strong><p><br>")
      @eliminated_investments << eliminated_investment[0]
      write_to_output( "<strong>Eliminated: Investment #{eliminated_investment[0]} (lowest vote count)</strong><br>")

      # Remove the eliminated investment from consideration
      initial_vote_counts.delete(eliminated_investment[0])

      # Transfer votes from the eliminated investment to the next preferences
      reallocated_votes = transfer_eliminated_votes(votes_data, eliminated_investment[0])
      write_to_output( "<p>Reallocating Votes from Ballots: #{reallocated_votes}</p>") unless reallocated_votes.empty?
      
      reallocated_votes.each do |id|
      if initial_vote_counts.key?(id)
         # Increment the vote count for the investment ID
           initial_vote_counts[id] += 1
           write_to_output( "<p>Reallocated vote to investment #{id}</p><br>")
      else
         # Optionally, handle the case where the investment ID is not found in the hash
          Rails.logger.warn "Investment ID #{id} not found in initial vote counts"
       end
  
      end
      
      # If there are no more seats left to fill, stop the loop
      break if empty_seats <= 0
    end

    # Output elected and eliminated investments for this iteration
    write_to_output( "<p><strong>End of round #{iteration} summary</strong></p><br>")
    write_to_output( "<p><strong>Elected Investments: #{@elected_investments.join(', ')}</strong></p><br>") unless @elected_investments.empty?
    write_to_output( "<p>Eliminated Investments: #{@eliminated_investments.join(', ')}</p>") unless @eliminated_investments.empty?
    write_to_output( "<p>-------------\n</p><br>")
    write_to_output( "<p>Remaining empty seats: #{empty_seats}</p><br><br>")

    # Increment iteration count
    iteration += 1
  end

  @elected_investments
end

def transfer_eliminated_votes(votes_data, eliminated_investment_id)
  reallocated_votes = []
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
          write_to_output( "<p>All next preferences for vote #{vote} are already elected or eliminated.</p>")
          break
        end

        next_preference_index += 1
      end
      
      vote[:rankings].shift  # Remove the eliminated investment from the first preference
    end
  end

  write_to_output( "Reallocated votes: #{reallocated_votes}")
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
  puts "Inspecting votes_data structure:"
  puts votes_data.inspect
  puts elected_investment_id
  #surplus_contributing_votes = votes_data.count { |_, vote| vote[:rankings].first == elected_investment_id }
  #transfer_ratio = surplus.to_f / surplus_contributing_votes
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
  write_to_output( "#{surplus_contributing_ballots}")
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