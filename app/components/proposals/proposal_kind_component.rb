# app/components/proposals/proposal_kind_component.rb
class Proposals::ProposalKindComponent < ApplicationComponent
  attr_reader :form

  def initialize(form)
    @form = form
  end

  def render?
    ProposalKind.count > 1
  end

  private

    def proposal_kind_options
      ProposalKind.order(:name).pluck(:name, :id)
    end
end
