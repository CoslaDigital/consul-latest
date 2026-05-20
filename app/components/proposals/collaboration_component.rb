# app/components/proposals/collaboration_component.rb
class Proposals::CollaborationComponent < ApplicationComponent
  # Changing these to reader attributes allows the view template
  # to safely see @proposal and @current_user
  attr_reader :proposal, :current_user

  delegate :status_label_class, :dom_id, to: :helpers

  def initialize(proposal, current_user)
    @proposal = proposal
    @current_user = current_user
  end

  def author?
    @current_user == @proposal.author
  end

  def render?
    # Don't show the collaboration box if the proposal is retired
    !proposal.retired?
  end
end
