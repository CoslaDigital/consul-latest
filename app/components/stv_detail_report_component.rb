# In app/components/stv_detail_report_component.rb

class StvDetailReportComponent < ViewComponent::Base
  def initialize(rounds:, investment_titles:)
    @rounds = rounds
    @investment_titles = investment_titles
  end
end