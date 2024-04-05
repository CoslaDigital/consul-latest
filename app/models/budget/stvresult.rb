class Budget
  class Stvresult
    attr_accessor :budget, :heading, :current_investment
    
    def initialize(budget, heading)
      @budget = budget
      @heading = heading
      @candidates = candidates
      @elected_investments = []
      @eliminated_investments = []
      log_file_name = "stv_budget_#{budget.id}_heading_#{heading.id}.log"
  
     # Configure the STV logger with the constructed file name
      @stv_logger = ActiveSupport::Logger.new(Rails.root.join('log', log_file_name))
    end
    
    def droop_quota(votes, seats)
      # votes = budget.ballots.sum(:ballot_lines_count)
      #votes = budget.ballots.count
      #seats = budget.stv_winners
      @stv_logger.info "Votes = #{votes}, Seats = #{seats}"
      (votes/(seats + 1)).floor + 1
    end  
    
    def calculate_stv_winners
      reset_winners
      reset_eliminateds
      seats = budget.stv_winners
      votes = budget.ballots.count
      quota = droop_quota(votes, seats) # Calculate the Droop quota once
      @stv_logger.info "the quota is #{@quota}"
      ballots = get_ballots
      ballot_data = get_votes_data
      @stv_logger.info "about to count votes"
      winners = calculate_results(ballot_data, seats, quota)
      @stv_logger.info "Election Complete"
      @stv_logger.info "Results are #{winners}"
      update_winning_investments(winners)
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
  # Initialize a hash to store the initial vote counts for each investment
  initial_vote_counts = Hash.new(0)
  # Fetch all investments
  investments = @heading.investments.where(budget_id: @budget.id, selected: true)

  # Initialize the hash with all investment IDs and set their initial count to 0
  initial_vote_counts = {}
    investments.each do |investment|
    @stv_logger.info "setting up #{investment.id}"
    initial_vote_counts[investment.id] = 0
  end
  empty_seats = seats
  @stv_logger.info "About to get the data, Seats to fill: #{empty_seats}"
  # Count the initial votes for each investment
  votes_data.each do |vote|
  if vote[:rankings].empty?
    Rails.logger.warn "Discarding invalid vote: #{vote}. Rankings are empty."
  else
    investment_id = vote[:rankings].first
    if initial_vote_counts.key?(investment_id)
      initial_vote_counts[investment_id] += 1
      @stv_logger.info "Initial vote counted for investment #{investment_id}"
    else
      Rails.logger.error "Invalid vote: Investment #{investment_id} does not exist."
    end
  end
   end
  # Initialize elected and eliminated investments arrays
  @elected_investments = []
  @eliminated_investments = []
  iteration = 1
  loop do
    @stv_logger.info "Round #{iteration}:"
    @stv_logger.info "----------------"
    @stv_logger.info "Quota is #{quota}"

    # Sort investments by their initial vote counts
    sorted_investments = initial_vote_counts.sort_by { |investment_id, count| -count }
    if sorted_investments.empty?
     @stv_logger.info "No more candidates to consider."
     break
    end
    # Output sorted investments to Rails logger
    @stv_logger.info("Remaining andidates in order of votes:")
       sorted_investments.each do |investment_id, count|
       @stv_logger.info("Investment ID: #{investment_id}, Vote Count: #{count}")
       investments.find_by(id: investment_id)&.update(votes: count)
    end
    # Check if there are any investments with enough votes to meet the quota
    elected_investment = sorted_investments.find { |investment_id, count| count >= quota }
    @stv_logger.info "elected investment #{elected_investment}"
    if elected_investment
      # Add the elected investment to the list of elected investments
      @elected_investments << elected_investment[0]
      @stv_logger.info "Elected: Investment #{elected_investment[0]} (exceeds quota)"

      # Calculate surplus votes and transfer them to next preferences
      surplus = elected_investment[1] - quota
      @stv_logger.info "surplus is #{surplus}"
      transfer_surplus_votes(votes_data, elected_investment[0], surplus)

      # Reduce the number of seats left to fill

      empty_seats -= 1
      @stv_logger.info "Remaining empty seats #{empty_seats}"
      # Remove the elected investment from consideration
      initial_vote_counts.delete(elected_investment[0])
      # Break if no more seats left to fill
      break if empty_seats <= 0
    else
      @stv_logger.info " No investments meet the quota, so eliminate the lowest-ranking investment"
      eliminated_investment = sorted_investments.last
      @stv_logger.info "Candidate to be eliminated #{eliminated_investment}"
      @eliminated_investments << eliminated_investment[0]
      @stv_logger.info "Eliminated: Investment #{eliminated_investment[0]} (lowest vote count)"

      # Remove the eliminated investment from consideration
      initial_vote_counts.delete(eliminated_investment[0])

      # Transfer votes from the eliminated investment to the next preferences
      reallocated_votes = transfer_eliminated_votes(votes_data, eliminated_investment[0])
      @stv_logger.info "Reallocating Votes from Ballots: #{reallocated_votes}" unless reallocated_votes.empty?
      
      reallocated_votes.each do |id|
      if initial_vote_counts.key?(id)
         # Increment the vote count for the investment ID
           initial_vote_counts[id] += 1
           @stv_logger.info "Reallocated vote to investment #{id}"
      else
         # Optionally, handle the case where the investment ID is not found in the hash
          Rails.logger.warn "Investment ID #{id} not found in initial vote counts"
       end
  
      end
      
      # If there are no more seats left to fill, stop the loop
      break if empty_seats <= 0
    end

    # Output elected and eliminated investments for this iteration
    @stv_logger.info "Elected Investments: #{@elected_investments.join(', ')}" unless @elected_investments.empty?
    @stv_logger.info "Eliminated Investments: #{@eliminated_investments.join(', ')}" unless @eliminated_investments.empty?
    @stv_logger.info "\n"
    @stv_logger.info "Remaining empty seats: #{empty_seats}"

    # Increment iteration count
    iteration += 1
  end

  @elected_investments
end

def transfer_eliminated_votes(votes_data, eliminated_investment_id)
  reallocated_votes = []
  votes_data.each do |vote|
    if vote[:rankings].first == eliminated_investment_id
      @stv_logger.info "Reallocating votes for #{eliminated_investment_id}"
      next_preference_index = 1

      loop do
        next_preference = vote[:rankings][next_preference_index]
        
        if next_preference && next_preference != eliminated_investment_id && !elected_or_eliminated?(next_preference)
          reallocated_votes << next_preference
          break
        elsif next_preference.nil? || next_preference == eliminated_investment_id
          Rails.logger.warn "All next preferences for vote #{vote} are already elected or eliminated."
          break
        end

        next_preference_index += 1
      end
      
      vote[:rankings].shift  # Remove the eliminated investment from the first preference
    end
  end

  @stv_logger.info "Reallocated votes: #{reallocated_votes}"
  reallocated_votes
end



def transfer_eliminated_votes_nearly(votes_data, eliminated_investment_id)
  reallocated_votes = []
  votes_data.each do |vote|
    if vote[:rankings].first == eliminated_investment_id
      @stv_logger.info "Reallocating votes for #{eliminated_investment_id}"
      next_preference = vote[:rankings][1]
      if next_preference && next_preference != eliminated_investment_id && !elected_or_eliminated?(next_preference)
        reallocated_votes << next_preference
      else
        Rails.logger.warn "Next preference for vote #{vote} is already elected or eliminated. Using next available preference."
        reallocated_votes << vote[:rankings].find { |id| !elected_or_eliminated?(id) }
      end      
      vote[:rankings].shift  # Remove the eliminated investment from the first preference
    end
  end
  @stv_logger.info "Rallocate votes #{reallocated_votes.flatten}"
  reallocated_votes.flatten
  
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

def transfer_surplus_votes(votes_data, elected_investment_id, surplus)
  # Calculate the number of votes that contributed to the surplus
  surplus_contributing_votes = votes_data.count { |vote| vote[:rankings].first == elected_investment_id }
  
  # Transfer surplus votes proportionally to next preferences
  votes_data.each do |vote|
    if vote[:rankings].first == elected_investment_id
      transfer_ratio = surplus.to_f / surplus_contributing_votes
    #  @stv_logger.info " transfer ratio #{transfer_ratio}"
      vote[:rankings].shift  # Remove the elected investment from the first preference

      vote[:rankings].each_with_index do |investment_id, index|
  # Increase each next preference vote count by the transfer_ratio
      vote[:rankings][index] = investment_id if index == 0  # Keep the first preference unchanged
      vote[:rankings][index] += transfer_ratio if index > 0  # Increase next preference votes by transfer_ratio
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


  def get_votes_data
  ballots = get_ballots
  votes_data = []

  ballots.each do |ballot|
    @stv_logger.info "Votes data #{votes_data}"
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
    
    def list_votes
      @candidates.each do |candidate|
         @stv_logger.info "candidate #{candidate.id}: votes #{candidate.votes}"
      end
    end
    
    def reset_winners
      candidates.update_all(winner: false)
      candidates.update_all(incompatible: false)
      candidates.update_all(votes: 0)
    end

    def reset_eliminateds
      candidates.update_all(eliminated: false)
    end

    def set_winner
      @money_spent += @current_investment.price
      @current_investment.update!(winner: true)
    end
    
    def eliminate
      @current_investment.update!(eliminated: true)
    end

    def winners
      investments.where(winner: true)
    end
    
    def get_elected_candidates
    @candidates.select { |candidate| candidate.winner }
  end
  end
end