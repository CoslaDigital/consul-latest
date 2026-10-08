# app/services/stv_calculator.rb
#
# Implements the Weighted Inclusive Gregory Method (WIGM) for STV.
#
# Ballots are "stateful": each one tracks its current transfer value and
# current candidate. This lets us correctly:
#   - transfer fractional surplus values
#   - preserve fractional values across subsequent eliminations
#   - track exhausted vote value (not just exhausted ballot counts)
#
class StvCalculator
  Result = Struct.new(
    :winners,
    :elimination_log,
    :unfilled_seats,
    :rounds,
    :exhausted_total,
    keyword_init: true
  )

  Ballot = Struct.new(:rankings, :current_value, :current_candidate, :exhausted, keyword_init: true)

  def initialize
    # no state; safe to reuse
  end

  def calculate(ballot_data, seats, initial_quota, investment_titles, dynamic_quota_enabled: false)
    reset_state
    @investment_titles = investment_titles
    @seats = seats
    @dynamic_quota = dynamic_quota_enabled

    @ballots = ballot_data.map do |vote|
      Ballot.new(
        rankings: vote[:rankings].dup,
        current_value: 1.0,
        current_candidate: vote[:rankings].first,
        exhausted: false
      )
    end

    @first_preference_votes = Hash.new(0.0)
    @ballots.each do |b|
      @first_preference_votes[b.current_candidate] += 1.0 if b.current_candidate
    end

    @active_candidates = investment_titles.keys
    @empty_seats = seats
    @iteration = 1
    @current_quota = initial_quota

    run_loop

    Result.new(
      winners: @elected_investments,
      elimination_log: @elimination_log,
      unfilled_seats: @empty_seats,
      rounds: @rounds_data,
      exhausted_total: @exhausted_total
    )
  end

  private

    def reset_state
      @elected_investments = []
      @eliminated_investments = []
      @elimination_log = []
      @rounds_data = []
      @exhausted_total = 0.0
      @history = Hash.new { |h, k| h[k] = [] }
    end

    def run_loop
      loop do
        update_dynamic_quota
        totals = tally_candidates

        totals.each { |id, total| @history[id] << total }
        candidates_over_quota = totals.select { |_, total| total >= @current_quota }

        if candidates_over_quota.any?
          handle_election(candidates_over_quota, totals)
        else
          handle_elimination(totals)
        end

        break if @empty_seats <= 0
        break if @active_candidates.size <= @empty_seats
        @iteration += 1
      end

      auto_elect_remaining if @empty_seats > 0 && @active_candidates.any?
    end

    def update_dynamic_quota
      return unless @dynamic_quota && @iteration > 1
      total_active_value = @ballots.sum { |b| b.exhausted ? 0.0 : b.current_value }
      @current_quota = droop_quota(total_active_value, @empty_seats)
    end

    def droop_quota(total_value, seats)
      return 0 if seats <= 0
      (total_value / (seats + 1)).floor + 1
    end

    def tally_candidates
      totals = Hash.new(0.0)
      @active_candidates.each { |id| totals[id] = 0.0 }
      @ballots.each do |b|
        next if b.exhausted
        next unless @active_candidates.include?(b.current_candidate)
        totals[b.current_candidate] += b.current_value
      end
      totals
    end

    # ------------------------------------------------------------------
    # Election (surplus transfer)
    # ------------------------------------------------------------------

    def handle_election(candidates_over_quota, totals)
      ordered = candidates_over_quota.sort_by { |id, total| [-total, id] }
      elected_id, elected_total = ordered.first

      surplus = elected_total - @current_quota
      title = @investment_titles[elected_id]

      unless @elected_investments.include?(elected_id)
        @elected_investments << elected_id
        @empty_seats -= 1
      end
      @active_candidates.delete(elected_id)

      transfer_fraction = (surplus > 0 && elected_total > 0) ? (surplus.to_f / elected_total) : nil
      transfers_to = Hash.new(0.0)

      if transfer_fraction && @empty_seats > 0
        @ballots
          .select { |b| !b.exhausted && b.current_candidate == elected_id }
          .each do |ballot|
          ballot.current_value *= transfer_fraction
          advance_ballot(ballot)
          transfers_to[ballot.current_candidate] += ballot.current_value if ballot.current_candidate
        end
      end

      action = {
        type: :election,
        title: title,
        candidate_id: elected_id,
        count: elected_total,
        surplus: [surplus, 0.0].max,
        transfer_fraction: transfer_fraction
      }

      log_round(totals, action, transfers: {
        type: :surplus,
        candidate_id: elected_id,
        amount: surplus,
        fraction: transfer_fraction,
        to: transfers_to
      })
    end

    # ------------------------------------------------------------------
    # Elimination (no surplus; ballots keep their current value)
    # ------------------------------------------------------------------

    def handle_elimination(totals)
      min_votes = totals.values.min
      tied = totals.select { |_, v| v == min_votes }

      eliminated_id, tie_break_info = if tied.size > 1
                                        result = resolve_scottish_tie(tied.keys)
                                        [result[:id], result]
                                      else
                                        [tied.keys.first, nil]
                                      end

      eliminated_votes = totals[eliminated_id]
      title = @investment_titles[eliminated_id] || "Unknown"

      @elimination_log << {
        round: @iteration,
        title: title,
        id: eliminated_id,
        votes: eliminated_votes
      }

      @eliminated_investments << eliminated_id unless @eliminated_investments.include?(eliminated_id)
      @active_candidates.delete(eliminated_id)

      transfers_to = Hash.new(0.0)
      before_exhausted = @exhausted_total

      @ballots
        .select { |b| !b.exhausted && b.current_candidate == eliminated_id }
        .each do |b|
        advance_ballot(b)
        transfers_to[b.current_candidate] += b.current_value if b.current_candidate
      end

      exhausted_this_round = @exhausted_total - before_exhausted

      action = {
        type: :elimination,
        title: title,
        candidate_id: eliminated_id,
        count: eliminated_votes,
        exhausted_value: exhausted_this_round
      }
      action[:tie_break_message] = format_tie_break_message(tie_break_info) if tie_break_info

      log_round(totals, action, transfers: {
        type: :elimination,
        candidate_id: eliminated_id,
        amount: eliminated_votes,
        to: transfers_to
      })
    end

    def advance_ballot(ballot)
      skip = @elected_investments + @eliminated_investments
      next_pref = ballot.rankings.find { |id| !skip.include?(id) }

      if next_pref
        ballot.current_candidate = next_pref
      else
        ballot.exhausted = true
        ballot.current_candidate = nil
        @exhausted_total += ballot.current_value
      end
    end

    # ------------------------------------------------------------------
    # Auto-election of remaining candidates
    # ------------------------------------------------------------------

    def auto_elect_remaining
      return if @active_candidates.empty?

      @active_candidates.dup.each do |id|
        break if @empty_seats <= 0
        next if @elected_investments.include?(id)

        round_totals = tally_candidates
        current_votes = round_totals[id] || 0.0

        @iteration += 1

        @elected_investments << id
        @empty_seats -= 1

        action = {
          type: :auto_election,
          title: @investment_titles[id],
          candidate_id: id,
          count: current_votes
        }

        log_round(round_totals, action, transfers: {})
      end
    end

    # ------------------------------------------------------------------
    # Tie-breaking
    # ------------------------------------------------------------------

    def resolve_scottish_tie(tied_ids)
      last_round = (@history[tied_ids.first] || []).size - 2
      if last_round >= 0
        last_round.downto(0) do |idx|
          comparison = tied_ids.each_with_object({}) { |id, h| h[id] = @history[id][idx] }
          min = comparison.values.min
          at_min = comparison.select { |_, v| v == min }.keys
          if at_min.size == 1
            return {
              id: at_min.first,
              reason: :previous_round,
              details: { round: idx + 1, comparison: comparison }
            }
          end
        end
      end

      comparison = tied_ids.each_with_object({}) { |id, h| h[id] = @first_preference_votes[id] }
      min = comparison.values.min
      at_min = comparison.select { |_, v| v == min }.keys
      if at_min.size == 1
        return {
          id: at_min.first,
          reason: :first_preference,
          details: { comparison: comparison }
        }
      end

      {
        id: at_min.sample,
        reason: :random_lot,
        details: { tied_candidates: at_min }
      }
    end

    def format_tie_break_message(info)
      return nil unless info

      case info[:reason]
      when :previous_round
        counts = info[:details][:comparison].map { |id, v| "#{@investment_titles[id]}: #{v.round(2)}" }.join(", ")
        "Tie resolved by votes at Round #{info[:details][:round]} (#{counts})."
      when :first_preference
        counts = info[:details][:comparison].map { |id, v| "#{@investment_titles[id]}: #{v.round(2)}" }.join(", ")
        "Tie resolved by first-preference votes (#{counts})."
      when :random_lot
        names = info[:details][:tied_candidates].map { |id| @investment_titles[id] }.join(", ")
        "Tie could not be resolved by previous rounds or first-preference counts; " \
          "random lot applied to: #{names}."
      end
    end

    # ------------------------------------------------------------------
    # Round logging
    # ------------------------------------------------------------------

    def log_round(totals, action, transfers:)
      @rounds_data << {
        iteration: @iteration,
        quota: @current_quota,
        standings: totals.sort_by { |id, total| [-total, id] }.to_h,
        action: action,
        transfers: transfers,
        exhausted_total: @exhausted_total
      }
    end
end
