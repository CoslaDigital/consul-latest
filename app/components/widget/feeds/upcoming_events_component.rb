# app/components/widget/feeds/upcoming_events_component.rb
class Widget::Feeds::UpcomingEventsComponent < ApplicationComponent
  attr_reader :event

  def initialize(event)
    @event = event
  end

  # Helper to calculate the title safely for all types (Budgets, Phases, Manual Events)
  def title
    @event.respond_to?(:calendar_title) ? @event.calendar_title : @event.name
  end

  # Helper to calculate the URL safely (Fixes the Budget Phase URL crash)
  def url
    @event.respond_to?(:calendar_link_url) ? @event.calendar_link_url : @event
  end

  # Helper for the date logic
  def date_object
    @event.respond_to?(:calendar_start) ? @event.calendar_start : @event.starts_at
  end
end
