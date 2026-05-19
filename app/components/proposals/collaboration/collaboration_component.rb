class Proposals::CollaborationComponent < ViewComponent::Base
  def initialize(proposal, current_user)
    @proposal = proposal
    @current_user = current_user
  end
end
