module Mappable
  extend ActiveSupport::Concern

  included do
    has_one :map_location, dependent: :destroy
    accepts_nested_attributes_for :map_location, allow_destroy: true, reject_if: :all_blank

    # Scopes out only records that have valid coordinates
    scope :geolocated, -> { joins(:map_location).where.not(map_locations: { latitude: nil, longitude: nil }) }
  end

  # Formats an individual record into our uniform front-end schema
  def map_payload(icon_class = "default-pin")
    return nil unless map_location&.available?

    {
      lat: map_location.latitude,
      long: map_location.longitude,
      title: try(:title) || try(:name) || "Location",
      link: Rails.application.routes.url_helpers.polymorphic_path(self, only_path: true),
      icon_class: icon_class,
      id: id
    }
  end

  class_methods do
    # Builds a flat layer configuration: e.g., Proposal.published.build_map_layer("Citizen Proposals", "proposal-pin")
    def build_map_layer(layer_name, icon_class)
      { layer_name => geolocated.map { |record| record.map_payload(icon_class) }.compact }
    end

    # Splits a collection dynamically by an attribute: e.g., Proposal.published.build_split_map_layers(:proposal_kind, "proposal-pin")
    def build_split_map_layers(group_attribute, icon_class_prefix)
      grouped_payload = {}

      # Group by the association object (e.g. proposal_kind) rather than just the raw ID column
      geolocated.includes(group_attribute.to_sym).group_by(&group_attribute.to_sym).each do |kind, items|
        # Grab the human-readable title or name method off the associated configuration model safely
        kind_name = kind&.name || "Proposal"
        kind_slug = kind&.slug || "proposal"

        layer_name = "#{model_name.human.pluralize}: #{kind_name}"
        icon_class = "#{icon_class_prefix}-#{kind_slug}"

        grouped_payload[layer_name] = items.map { |item| item.map_payload(icon_class) }.compact
      end

      grouped_payload
    end
  end
end
