# app/components/stv_summary_report_component.rb

class StvSummaryReportComponent < ViewComponent::Base
  include StvFormatting

  attr_reader :result, :budget, :heading, :candidates, :votes_cast, :quota,
              :report_title, :detail_page_slug, :dynamic_quota_enabled

  def initialize(result:, budget:, heading:, candidates:, votes_cast:, quota:,
                 report_title:, detail_page_slug: nil, dynamic_quota_enabled: false)
    @result = result
    @budget = budget
    @heading = heading
    @candidates = candidates
    @votes_cast = votes_cast
    @quota = quota
    @report_title = report_title
    @detail_page_slug = detail_page_slug
    @dynamic_quota_enabled = dynamic_quota_enabled
  end

  # Total number of seats contested (filled + unfilled).
  def total_seats
    @result.unfilled_seats + @result.winners.size
  end

  # Candidates sorted alphabetically by title for the ballot list.
  def sorted_candidate_titles
    @candidates.map(&:title).sort
  end

  # Look up a candidate object by id.
  def candidate_for(id)
    @candidates.find { |c| c.id == id }
  end

  # Find the round in which the given candidate was elected/auto-elected.
  def election_round_for(candidate_id)
    @result.rounds.find do |r|
      r[:action]&.dig(:candidate_id) == candidate_id &&
        %i[election auto_election].include?(r[:action][:type])
    end
  end

  # Human-readable description for a winner line.
  def winner_description(winner_id)
    round = election_round_for(winner_id)
    return "—" unless round

    action = round[:action]
    case action[:type]
    when :election
      "elected in round #{round[:iteration]} with #{format_votes(action[:count])} votes"
    when :auto_election
      "auto-elected in round #{round[:iteration]} to fill a remaining seat"
    end
  end
end
