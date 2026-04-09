class Offers::NewComponent < ApplicationComponent
  include Header

  attr_reader :offer
  delegate :new_window_link_to, to: :helpers

  def initialize(offer)
    @offer = offer
  end

  def title
    t("offers.new.start_new", default: "Create a new Offer")
  end
end
