# app/components/stv_detail_report_component.rb

class StvDetailReportComponent < ViewComponent::Base
  include StvFormatting

  attr_reader :rounds, :investment_titles, :dynamic_quota_enabled

  def initialize(rounds:, investment_titles:, dynamic_quota_enabled: false, heading: nil)
    @rounds = rounds
    @investment_titles = investment_titles
    @dynamic_quota_enabled = dynamic_quota_enabled
    @heading = heading
  end

  # Look up a candidate title by id.
  def title_for(id)
    @investment_titles[id] || "Unknown"
  end

  # Round standings sorted highest -> lowest, with a stable tie-break by id.
  def sorted_standings(round)
    round[:standings].sort_by { |id, total| [-total, id] }.to_h
  end

  # The lowest-standing candidate in a round (the elimination target).
  def lowest_candidate_id(round)
    sorted_standings(round).to_a.last&.first
  end

  # Delta between two rounds for a given candidate, or nil if this is round 1.
  def delta_for(round, candidate_id, previous_round)
    return nil unless previous_round
    current = round[:standings][candidate_id] || 0.0
    previous = previous_round[:standings][candidate_id] || 0.0
    current - previous
  end

  # Status label for a standings row.
  # Status label for a standings row.
  # Marks every candidate at quota, and every candidate tied for the lowest total.
  def status_for(round, candidate_id)
    total = round[:standings][candidate_id]
    return "" if total.nil?

    return "✓ At quota" if total >= round[:quota]

    min_votes = round[:standings].values.min
    return "⚠ Lowest" if total == min_votes

    ""
  end

  # Total active value in a round.
  def active_total(round)
    round[:standings].values.sum
  end

  # The `:to` hash of a round's transfers, or an empty hash.
  def transfers_for(round)
    round.dig(:transfers, :to) || {}
  end

  # Retained value for a given round: the quota-worth of votes held by each
  # candidate elected in a *previous* round. These votes are no longer active
  # (they've left the continuing count) but are not exhausted.
  def retained_total_for(round, all_rounds)
    round_index = all_rounds.index(round)
    return 0.0 if round_index.nil? || round_index.zero?

    previous_rounds = all_rounds[0...round_index]

    previous_rounds.sum do |prev_round|
      action = prev_round[:action]
      next 0.0 unless action

      case action[:type]
      when :election
        prev_round[:quota].to_f
      when :auto_election
        action[:count].to_f
      else
        0.0
      end
    end
  end

  # Active + retained + exhausted should always equal the total valid votes cast.
  def grand_total(round, all_rounds)
    active_total(round) + retained_total_for(round, all_rounds) + round[:exhausted_total].to_f
  end

end
