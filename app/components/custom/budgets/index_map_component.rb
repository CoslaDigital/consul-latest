class Budgets::IndexMapComponent < ApplicationComponent
  delegate :render_map, to: :helpers
  attr_reader :budgets

  def initialize(budgets)
    @budgets = budgets
  end

  def render?
    feature?(:map) && budgets.any?
  end

  private

    def coordinates
      # We return an empty array here because we only want to show geozone outlines,
      # not individual investment/project pins at this stage.
      []
    end

    def geozones_data
      # 1. Get all headings belonging to these active budgets that have a geozone attached
      headings = Budget::Heading.joins(group: :budget)
                                .where(budget_groups: { budget_id: budgets.map(&:id) })
                                .where.not(geozone_id: nil)
                                .includes(:geozone, group: :budget)

      # 2. Group the headings by their associated geozone
      grouped_headings = headings.group_by(&:geozone)

      # 3. Format the data for the Consul map engine
      grouped_headings.map do |geozone, geozone_headings|
        {
          outline_points: geozone.outline_points,
          color: geozone.color,
          name: geozone.name,
          # Create a popup link to the specific heading page when the geozone is clicked
          headings: geozone_headings.map do |heading|
            budget = heading.group.budget
            # Links directly to the candidate/investment list for this specific heading
            link_to heading.name, budget_investments_path(budget, heading_id: heading.id)
          end.uniq
        }
      end
    end
end
