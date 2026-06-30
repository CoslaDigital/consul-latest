# app/components/offers/mine_component.rb
class Offers::MineComponent < ApplicationComponent
  attr_reader :user

  def initialize(user:, current_filter: nil)
    @user = user
    @params_filter = current_filter
  end

  def current_filter
    if valid_filters.include?(@params_filter)
      @params_filter
    else
      # Defaults to the first tab that actually has items
      valid_filters.first
    end
  end

  # DYNAMIC LOGIC: Only returns filters if there are items inside them
  def valid_filters
    filters = []
    filters << "resources_offered" if offers_offered.any?
    filters << "help_received" if help_received.any?

    # Fallback: If both are empty, default to "resources_offered"
    # so the page still renders an empty state gracefully.
    filters.present? ? filters : ["resources_offered"]
  end

  def count(filter)
    case filter
    when "resources_offered" then offers_offered.count
    when "help_received" then help_received.count
    else 0
    end
  end

  def offers_offered
    @offers_offered ||= user.offers.order(created_at: :desc)
  end

  def help_received
    @help_received ||= ProposalMatch.where(proposal_id: user.proposals.pluck(:id))
                                    .includes(:offer, proposal: :author)
                                    .order(created_at: :desc)
  end
end
