class Admin::ProposalKinds::FormComponent < ApplicationComponent
  attr_reader :proposal_kind, :title

  def initialize(proposal_kind, title:)
    @proposal_kind = proposal_kind
    @title = title
  end
end
