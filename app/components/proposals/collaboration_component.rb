class Proposals::CollaborationComponent < ApplicationComponent
  attr_reader :proposal, :current_user

  def initialize(proposal, current_user)
    @proposal = proposal
    @current_user = current_user
  end

  def render?
    # Don't show the collaboration box if the proposal is retired or the user isn't verified
    !proposal.retired?
    true
  end

  private

    def existing_match
      return nil unless current_user
      @existing_match ||= proposal.proposal_matches.where(offer_id: current_user.offers.pluck(:id)).first
    end

    def user_offers
      @user_offers ||= current_user.offers.active
    end
end
