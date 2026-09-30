# Load the original files first to ensure they exist in memory before we patch them
load Rails.root.join("app", "controllers", "admin", "budget_headings_controller.rb")

# Reopen the module to override the allowed_params method
module Admin::BudgetHeadingsActions
  private

    def allowed_params
      # Add :max_winners to the list of valid attributes
      valid_attributes = [
        :price, :population, :allow_custom_content, :latitude, :longitude,
        :max_ballot_lines, :geozone_id, :geozone_restricted, :max_winners,
        geozone_ids: []
      ]

      [*valid_attributes, translation_params(Budget::Heading)]
    end
end
