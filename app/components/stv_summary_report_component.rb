class StvSummaryReportComponent < ViewComponent::Base
  attr_reader :result, :budget, :heading, :candidates, :votes_cast, :quota, :report_title, :detail_page_slug

  def initialize(result:, budget:, heading:, candidates:, votes_cast:, quota:, report_title:, detail_page_slug: nil)
    @result = result
    @budget = budget
    @heading = heading
    @candidates = candidates
    @votes_cast = votes_cast
    @quota = quota
    @report_title = report_title
    @detail_page_slug = detail_page_slug
  end
end