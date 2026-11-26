module Events
  class IcalendarBuilder
    def initialize(items, view_context:, calendar_name: "Events Calendar")
      @items = Array(items)
      @view_context = view_context
      @calendar_name = calendar_name
    end

    def to_ics
      cal = Icalendar::Calendar.new
      cal.append_custom_property("X-WR-CALNAME", @calendar_name)

      @items.each do |item|
        next if item.calendar_start.blank?

        cal.event do |e|
          e.uid = "#{item.class.name.parameterize}-#{item.id}@#{@view_context.request.host}"
          e.dtstart = format_time(item.calendar_start)
          e.dtend = format_time(item.try(:calendar_end) || item.calendar_start)
          e.summary = item.calendar_title
          e.description = item.try(:description).to_s
          e.location = item.try(:location) if item.try(:location).present?
          e.url = absolute_url(item.calendar_link_url)

          if item.respond_to?(:map_location) && item.map_location&.available?
            e.geo = [item.map_location.latitude, item.map_location.longitude]
          end
        end
      end

      cal.publish
      cal.to_ical
    end

    private

      def format_time(value)
        if value.is_a?(Date) && !value.is_a?(Time)
          Icalendar::Values::Date.new(value)
        else
          Icalendar::Values::DateTime.new(value.utc, "tzid" => "UTC")
        end
      end

      def absolute_url(target)
        return if target.blank?

        URI.join(@view_context.request.base_url, @view_context.url_for(target)).to_s
      end
  end
end
