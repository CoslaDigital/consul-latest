class Proposals::FormComponent < ApplicationComponent; end

load Rails.root.join("app", "components", "proposals", "form_component.rb")

class Proposals::FormComponent < ApplicationComponent
  include TranslatableFormHelper
  include GlobalizeHelper
  attr_reader :proposal, :url
  delegate :current_user, :suggest_data, :geozone_select_options, to: :helpers

  def initialize(proposal, url:)
    @proposal = proposal
    @url = url
  end

  private

    def categories
      Tag.category.order(:name)
    end

    def proposal_kind_options
      ProposalKind.order(:name).pluck(:name, :id)
    end
end
