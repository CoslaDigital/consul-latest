class Proposals::Collaboration::ActiveTasksComponent < ViewComponent::Base
  def initialize(proposal, current_user)
    @proposal = proposal
    @current_user = current_user
  end

  def author?
    @current_user == @proposal.author
  end
end
