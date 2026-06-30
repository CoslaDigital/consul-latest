# app/helpers/admin/cards_helper.rb
module Admin
  module CardsHelper
    # Use a constant for the special homepage value to avoid magic strings.
    HOMEPAGE_CARD_VALUE = "SiteCustomization::Page_".freeze

    # Generates the full list of options for the dropdown.
    def cardable_options
      # Start with our clear, self-documenting Homepage option.
      options = [["Homepage (no parent)", HOMEPAGE_CARD_VALUE]]

      # Iterate through each potential parent model.
      cardable_classes.each do |klass|
        # EFFICIENTLY load only the data we need (id and a display column).
#        records = klass.select(:id, display_column_for(klass)).find_each
        
        klass.find_each do |record|
          options << [
            display_name_for_cardable(record),
            "#{record.class.name}_#{record.id}"
          ]
        end
      end

      options
    end

    # Determines which option should be pre-selected in the dropdown.
    def selected_cardable_option(card)
      # Check for the specific "homepage card" state.
      if card.cardable_type == "SiteCustomization::Page" && card.cardable_id.nil?
        HOMEPAGE_CARD_VALUE
      elsif card.cardable.present?
        "#{card.cardable_type}_#{card.cardable_id}"
      end
    end

    private

    # This finds all models that can be a parent to a card.
    # Caching this prevents a slow, app-wide scan on every page load.
    def cardable_classes
      Rails.cache.fetch("cardable_classes", expires_in: 1.hour) do
        Rails.application.eager_load!
        ApplicationRecord.descendants.select do |klass|
          klass.included_modules.include?(Cardable) && !klass.abstract_class?
        end
      end
    end
    
    # Creates a display name like "Custom Page: About Us".
    def display_name_for_cardable(record)
    prefix = record.class.model_name.human
    
    # Use the safe display_column_for helper to get the attribute name
    attribute_to_use = display_column_for(record.class)
    display_text = record.public_send(attribute_to_use)

    # Fallback to the ID if the display text is blank
    name = display_text.presence || "##{record.id}"
    
    "#{prefix}: #{name}"
  end

  # This is the corrected helper. It's now more specific.
  def display_column_for(klass)
    # Explicitly use :title for SiteCustomization::Page
    if klass == ::SiteCustomization::Page
      :title
    elsif klass.column_names.include?("title")
      :title
    elsif klass.column_names.include?("name")
      :name
    else
      # As a safe fallback, use the ID column if neither exists.
      :id
    end
  end
end
end