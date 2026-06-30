class Proposals::Collaboration::VisitorActionComponent < ViewComponent::Base
  # Delegate helpers so status_label_class works
  delegate :status_label_class, to: :helpers

  def initialize(proposal, current_user)
    @proposal = proposal
    @current_user = current_user
  end

  def author?
    @current_user == @proposal.author
  end
end
