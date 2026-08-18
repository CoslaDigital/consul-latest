module Mappable
  extend ActiveSupport::Concern

  included do
    has_one :map_location, dependent: :destroy
    accepts_nested_attributes_for :map_location, allow_destroy: true, reject_if: :all_blank

    scope :geolocated, -> { joins(:map_location).where.not(map_locations: { latitude: nil, longitude: nil }) }
  end

  def map_payload(icon_class = "default-pin")
    return nil unless map_location&.available?

    {
      lat: map_location.latitude,
      long: map_location.longitude,
      title: try(:title) || try(:name) || "Location",
      link: Rails.application.routes.url_helpers.polymorphic_path(self, only_path: true),
      icon_class: icon_class, # Passes the CSS class to the Javascript!
      id: id
    }
  end

  class_methods do
    def build_map_layer(layer_name, icon_class)
      { layer_name => geolocated.map { |record| record.map_payload(icon_class) }.compact }
    end

    def build_split_map_layers(group_attribute, icon_class_prefix)
      grouped_payload = {}

      geolocated.includes(group_attribute.to_sym).group_by(&group_attribute.to_sym).each do |kind, items|
        # Merged approach: Safely tries to get the name, but falls back to "General" if it's nil
        kind_name = (kind.respond_to?(:name) ? kind.name : kind.to_s.humanize).presence || "General"
        kind_slug = (kind.respond_to?(:slug) ? kind.slug : kind.to_s.parameterize).presence || "general"

        layer_name = "#{model_name.human.pluralize}: #{kind_name}"
        icon_class = "#{icon_class_prefix}-#{kind_slug}"

        grouped_payload[layer_name] = items.map { |item| item.map_payload(icon_class) }.compact
      end

      grouped_payload
    end
  end
end
