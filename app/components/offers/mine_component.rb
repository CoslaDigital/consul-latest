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
      valid_filters.first
    end
  end

  def valid_filters
    ["resources_offered", "help_received"]
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
