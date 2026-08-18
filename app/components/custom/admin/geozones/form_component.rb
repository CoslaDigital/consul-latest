class Admin::Geozones::FormComponent < ApplicationComponent; end

load Rails.root.join("app", "components", "admin", "geozones", "form_component.rb")

class Admin::Geozones::FormComponent < ApplicationComponent
  attr_reader :geozone

  def initialize(geozone)
    @geozone = geozone
  end

  def parent_options
    # Fetch all geozones ordered alphabetically
    candidates = Geozone.order(:name)

    # If editing an existing geozone, exclude it and its children from the dropdown
    # to prevent circular nesting loops.
    if geozone.persisted?
      candidates = candidates.where.not(id: geozone.self_and_descendant_ids)
    end

    candidates.map { |g| [g.name, g.id] }
  end
end
