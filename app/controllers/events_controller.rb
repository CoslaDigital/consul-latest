# frozen_string_literal: true

class EventsController < ApplicationController
  skip_authorization_check

  def index
    @start_date = resolve_start_date(params[:start_date])

    @calendar_items = Event.all_in_range(
      @start_date.beginning_of_month,
      @start_date.end_of_month
    )
  end

  def show
    @event = Event.find(params[:id])
  end

  private

  def resolve_start_date(date_param)
    return Date.current if date_param.blank?

    date_string = date_param.to_s

    # Strategy 1: ISO
    Date.iso8601(date_string)
  rescue ArgumentError
    # Strategy 2: Locale
    begin
      Date.strptime(date_string, I18n.t("date.formats.default"))
    rescue ArgumentError, TypeError
      # Strategy 3: Fallback
      Date.current
    end
  end
end
