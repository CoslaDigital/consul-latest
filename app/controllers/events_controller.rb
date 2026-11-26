# frozen_string_literal: true

class EventsController < ApplicationController
  skip_authorization_check

  def index
    respond_to do |format|
      format.html do
        @start_date = resolve_start_date(params[:start_date])
        @calendar_items = Event.all_in_range(
          @start_date.beginning_of_month,
          @start_date.end_of_month
        )
      end

      format.ics do
        feed_items = Event.all_in_range(1.month.ago, 12.months.from_now)
        ics = Events::IcalendarBuilder.new(
          feed_items,
          view_context: view_context,
          calendar_name: Setting["org_name"].presence || "Events Calendar"
        ).to_ics

        send_data ics,
                  type: "text/calendar; charset=utf-8",
                  disposition: "inline",
                  filename: "events.ics"
      end
    end
  end

  def show
    @event = Event.find(params[:id])

    respond_to do |format|
      format.html
      format.ics do
        ics = Events::IcalendarBuilder.new(
          @event,
          view_context: view_context
        ).to_ics

        send_data ics,
                  type: "text/calendar; charset=utf-8",
                  disposition: "attachment",
                  filename: "#{@event.name.parameterize}.ics"
      end
    end
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
