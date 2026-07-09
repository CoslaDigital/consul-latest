class Proposals::MapComponent < ApplicationComponent
  attr_reader :proposals, :split_by_kind
  delegate :render_map, to: :helpers

  def initialize(proposals, heading: nil, split_by_kind: true)
    # Target the collection passed from the view
    @proposals = proposals
    @split_by_kind = split_by_kind
  end

  def render?
    feature?(:map)
  end

  def coordinates
    # Chain straight off the already-filtered collection view variable
    map_proposals = @proposals.geolocated

    # If we are looking at a specific project kind, group by that kind natively.
    # Otherwise, split all of them out by their respective kinds.
    if split_by_kind && map_proposals.respond_to?(:klass) && map_proposals.klass.column_names.include?("proposal_kind_id")
      map_proposals.build_split_map_layers(:proposal_kind, "proposal-pin")
    else
      map_proposals.build_map_layer("Citizen Proposals", "proposal-pin")
    end
  end

  def geozones_data
    geozone_ids = @proposals.map(&:geozone_id).compact.uniq
    geozones = Geozone.where(id: geozone_ids)

    geozones.map do |geozone|
      {
        outline_points: geozone.outline_points,
        color: geozone.color,
        headings: [geozone.name],
        name: geozone.name
      }
    end
  end
end
