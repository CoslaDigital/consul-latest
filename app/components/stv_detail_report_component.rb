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
end
