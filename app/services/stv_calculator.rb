class StvCalculator
  # The Result struct now includes a log of all rounds for the detail component.
  Result = Struct.new(:winners, :elimination_log, :unfilled_seats, :rounds, keyword_init: true)

  # The calculator is stateless, so the initializer is empty.
  def initialize
  end
  
  # The main public method that runs the STV algorithm.
def calculate(ballot_data, seats, quota, investment_titles)
  # --- 1. Setup Phase ---
  initial_vote_counts = {}
  investment_titles.keys.each { |id| initial_vote_counts[id] = 0 }

  ballot_data.each do |vote|
    next if vote[:rankings].empty?
    investment_id = vote[:rankings].first
    initial_vote_counts[investment_id] += 1 if initial_vote_counts.key?(investment_id)
  end

  @elected_investments = []
  @eliminated_investments = []
  @elimination_log = []
  rounds_log = []
  empty_seats = seats
  iteration = 1
  # Store a copy of the original votes for tie-breaking
  first_preference_votes = initial_vote_counts.dup

  # Initialize a hash to store vote history
  vote_history = Hash.new { |h, k| h[k] = [] }


  # --- 2. Calculation Loop ---
  loop do
    sorted_investments = initial_vote_counts.sort_by { |_, count| -count }
    if sorted_investments.empty? || empty_seats <= 0
      break
    end

    current_round_data = {
      iteration: iteration,
      quota: quota,
      standings: sorted_investments,
      action: nil
    }

    elected_in_round = sorted_investments.select { |_, count| count >= quota }

    if elected_in_round.present?
      election_details = []
      elected_in_round.each do |investment_id, count|
        break if empty_seats <= 0
        @elected_investments << investment_id
        title = investment_titles[investment_id]
        surplus = count - quota

        reallocated_votes = transfer_surplus_votes(ballot_data, investment_id)
        if surplus > 0 && reallocated_votes.any?
          ratio = surplus.to_f / reallocated_votes.size
          reallocated_votes.each do |id|
            initial_vote_counts[id] += ratio if initial_vote_counts.key?(id)
          end
        end

        election_details << { id: investment_id, title: title, count: count, surplus: surplus }
        empty_seats -= 1
        initial_vote_counts.delete(investment_id)
      end
      current_round_data[:action] = { type: :election, details: election_details }
    else
      # --- Elimination Logic ---
      min_votes = sorted_investments.last[1]
      tied_candidates = sorted_investments.select { |_, count| count == min_votes }
      elimination_details = {}
      
      if tied_candidates.size > 1
        # A tie has occurred, call the new tie-breaking method
          tied_ids = tied_candidates.map { |id, _| id }
          tie_break_result = resolve_scottish_tie(tied_ids, vote_history, first_preference_votes)
          eliminated_id = tie_break_result[:id]
          
          # Log the reason for the report
          elimination_details[:tie_break_message] = format_tie_break_message(tie_break_result, investment_titles)
      else
        # No tie
        eliminated_id = tied_candidates.first[0]
      end

      # FIX 1: Get the vote count from the main hash, not the old variable.
      eliminated_votes = initial_vote_counts[eliminated_id]
      eliminated_title = investment_titles[eliminated_id] || "Unknown Candidate"
      
      # Update state
      @elimination_log << { round: iteration, title: eliminated_title, id: eliminated_id, votes: eliminated_votes }
      @eliminated_investments << eliminated_id
      initial_vote_counts.delete(eliminated_id)

      # Transfer votes
      transfer_result = transfer_eliminated_votes(ballot_data, eliminated_id)
      reallocated_votes = transfer_result[:reallocated]
      exhausted_count = transfer_result[:exhausted]

      reallocated_votes.each do |id|
        initial_vote_counts[id] += 1 if initial_vote_counts.key?(id)
      end
      
      # FIX 2: Removed a redundant `.merge!` call and simplified this assignment.
      elimination_details.merge!({
        id: eliminated_id,
        title: eliminated_title,
        count: eliminated_votes,
        reallocated_count: reallocated_votes.size,
        exhausted_count: exhausted_count
      })
      current_round_data[:action] = { type: :elimination, details: elimination_details }
    end

    rounds_log << current_round_data
    iteration += 1
  end

  # --- 3. Final Result ---
  Result.new(
    winners: @elected_investments,
    elimination_log: @elimination_log,
    unfilled_seats: seats - @elected_investments.size,
    rounds: rounds_log
  )
end

  
  private
  
  def format_tie_break_message(tie_break_result, investment_titles)
  details = tie_break_result[:details]
  
  case tie_break_result[:reason]
  when :previous_round
    comparison_text = details[:comparison].map do |id, count|
      "#{investment_titles[id]}: #{count.round(2)}"
    end.join(', ')
    "Tie resolved by checking votes from Round #{details[:round]}. Counts were: #{comparison_text}."
  when :first_preference
    comparison_text = details[:comparison].map do |id, count|
      "#{investment_titles[id]}: #{count.round(2)}"
    end.join(', ')
    "Tie resolved by checking original first preference votes. Counts were: #{comparison_text}."
  when :random_lot
    tied_names = details[:tied_candidates].map { |id| investment_titles[id] }.join(', ')
    "Tie could not be resolved by vote counts. A random draw was used to select a candidate for elimination from: #{tied_names}."
  end
  end
  
  def resolve_scottish_tie(tied_ids, vote_history, first_preference_votes)
  # Rule 1: Check previous rounds' votes.
  last_round_index = (vote_history[tied_ids.first] || []).size - 1
  if last_round_index >= 0
    (last_round_index).downto(0) do |round_idx|
      comparison = tied_ids.each_with_object({}) { |id, h| h[id] = vote_history[id][round_idx] }
      min_past_vote = comparison.values.min
      candidates_at_min = comparison.keys.filter { |id| comparison[id] == min_past_vote }
      
      if candidates_at_min.size == 1
        return { id: candidates_at_min.first, reason: :previous_round, 
                 details: { round: round_idx + 1, comparison: comparison } }
      end
    end
  end

  # Rule 2: Check first preference votes.
  comparison = tied_ids.each_with_object({}) { |id, h| h[id] = first_preference_votes[id] }
  min_first_pref = comparison.values.min
  candidates_at_min_first_pref = comparison.keys.filter { |id| comparison[id] == min_first_pref }
  
  if candidates_at_min_first_pref.size == 1
    return { id: candidates_at_min_first_pref.first, reason: :first_preference, 
             details: { comparison: comparison } }
  end

  # Rule 3: Decide by lot.
  { id: candidates_at_min_first_pref.sample, reason: :random_lot, 
    details: { tied_candidates: candidates_at_min_first_pref } }
  end
   
  def transfer_eliminated_votes(ballot_data, eliminated_investment_id)
    reallocated_votes = []
    exhausted_count = 0
    ballot_data.each do |vote|
      if vote[:rankings].first == eliminated_investment_id
        vote[:rankings].shift
        next_preference = vote[:rankings].find { |id| !elected_or_eliminated?(id) }
        if next_preference
          reallocated_votes << next_preference
        else
          exhausted_count += 1
        end
      end
    end
    # Return a hash with both sets of data
    { reallocated: reallocated_votes, exhausted: exhausted_count }
  end
  
  def transfer_surplus_votes(ballot_data, elected_investment_id)
    surplus_contributing_ballots = []
    ballot_data.each do |vote|
      if vote[:rankings].first == elected_investment_id
        vote[:rankings].shift
        next_preference = vote[:rankings].find { |id| !elected_or_eliminated?(id) }
        surplus_contributing_ballots << next_preference if next_preference
      end
    end
    surplus_contributing_ballots
  end

  def elected_or_eliminated?(investment_id)
    @elected_investments.include?(investment_id) || @eliminated_investments.include?(investment_id)
  end
end