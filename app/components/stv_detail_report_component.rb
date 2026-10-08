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

  # Vote value retained by already-elected candidates in this round.
  # Elected candidates hold `quota` worth of votes; these are neither active
  # (no longer part of the continuing count) nor exhausted.
  def retained_total(round)
    round[:retained_total] || 0.0
  end

  # Active + retained + exhausted should always equal the total valid votes cast.
  def grand_total(round)
    active_total(round) + retained_total(round) + round[:exhausted_total].to_f
  end

end
