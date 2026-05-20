class Proposals::ProposalKindComponent < ApplicationComponent
  attr_reader :form

  def initialize(form)
    @form = form
  end

  def render?
    ProposalKind.any?
  end

  private

    def proposal_kind_options
      ProposalKind.order(:name).pluck(:name, :id)
    end
end
