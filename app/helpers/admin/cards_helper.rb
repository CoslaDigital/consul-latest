# app/helpers/admin/cards_helper.rb
module Admin
  module CardsHelper
    # This method is already correct. It generates the full list of options.
    def cardable_options
      options = [["Homepage", "homepage_nil"]]

      cardable_classes.each do |klass|
        klass.all.each do |record|
          options << [
            display_name_for_cardable(record),
            "#{record.class.name}_#{record.id}"
          ]
        end
      end

      options
    end

    # ==> ADD THIS NEW HELPER METHOD <==
    # It determines which option should be pre-selected in the dropdown.
    def selected_cardable_option(card)
      if card.cardable_id.nil?
        "homepage_nil"
      else
        "#{card.cardable_type}_#{card.cardable_id}"
      end
    end

    private

    def cardable_classes
      Rails.application.eager_load!
      ApplicationRecord.descendants.select do |klass|
        klass.included_modules.include?(Cardable) && !klass.abstract_class?
      end
    end

    def display_name_for_cardable(record)
      prefix = record.class.model_name.human
      if record.respond_to?(:title) && record.title.present?
        "#{prefix}: #{record.title}"
      elsif record.respond_to?(:name) && record.name.present?
        "#{prefix}: #{record.name}"
      else
        "#{prefix} ##{record.id}"
      end
    end
  end
end