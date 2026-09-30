class StvDetailReportComponent < ViewComponent::Base
  # Add dynamic_quota_enabled to the initializer and attr_reader
  attr_reader :rounds, :investment_titles, :dynamic_quota_enabled

  def initialize(rounds:, investment_titles:, dynamic_quota_enabled: false)
    @rounds = rounds
    @investment_titles = investment_titles
    @dynamic_quota_enabled = dynamic_quota_enabled
  end
end