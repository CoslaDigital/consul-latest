class Admin::ProposalKinds::IndexComponent < ApplicationComponent
  attr_reader :proposal_kinds

  def initialize(proposal_kinds)
    @proposal_kinds = proposal_kinds
  end
end
