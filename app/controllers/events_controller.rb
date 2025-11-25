# frozen_string_literal: true

class EventsController < ApplicationController
  skip_authorization_check
  def index
    @events = Budget.published.open.includes(:phases)
  end
end
