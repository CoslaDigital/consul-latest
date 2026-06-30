class Proposals::Collaboration::HistoryComponent < ViewComponent::Base
  def initialize(proposal)
    @proposal = proposal
  end

  def render?
    @proposal.proposal_matches.fulfilled.any?
  end
end
