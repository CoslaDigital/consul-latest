class Offers::FormComponent < ApplicationComponent

  attr_reader :offer, :url
  delegate :suggest_data, :geozone_select_options, to: :helpers

  def initialize(offer, url:)
    @offer = offer
    @url = url
  end

  private

    def categories
      Tag.category.order(:name)
    end

end
