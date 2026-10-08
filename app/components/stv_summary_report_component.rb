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

  # The vote total for a candidate in the last round in which they appeared
  # in the standings. Used to show votes for auto-elected candidates.
  def final_standing_for(candidate_id)
    @result.rounds
           .reverse
           .find { |r| r[:standings].key?(candidate_id) }
      &.dig(:standings, candidate_id)
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
      votes = final_standing_for(winner_id)
      vote_text = votes ? "with #{format_votes(votes)} votes" : ""
      "deemed elected in round #{round[:iteration]} #{vote_text} " \
        "(Rule 53 — continuing candidates equal remaining vacancies)".strip
    else
      "elected in round #{round[:iteration]}"
    end
  end

  # True when the election finished with auto-election of one or more winners.
  def any_auto_elected?
    @result.winners.any? do |winner_id|
      election_round_for(winner_id)&.dig(:action, :type) == :auto_election
    end
  end
end
