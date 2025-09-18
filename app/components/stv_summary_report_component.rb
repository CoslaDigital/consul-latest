class StvSummaryReportComponent < ViewComponent::Base
  # Add :dynamic_quota_enabled to the attr_reader
  attr_reader :result, :budget, :heading, :candidates, :votes_cast, :quota, 
              :report_title, :detail_page_slug, :dynamic_quota_enabled

  # Add the keyword to the initialize method signature
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
    @dynamic_quota_enabled = dynamic_quota_enabled # Set the instance variable
  end
end