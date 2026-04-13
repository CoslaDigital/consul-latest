class Offers::EditComponent < ApplicationComponent
  include Header

  attr_reader :offer

  def initialize(offer)
    @offer = offer
  end

  private

    # The Header module automatically looks for this method
    def title
      t("offers.edit.title", default: "Edit your Offer")
    end
end
