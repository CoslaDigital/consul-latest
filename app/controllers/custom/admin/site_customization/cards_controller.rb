load Rails.root.join("app", "controllers", "admin", "site_customization", "cards_controller.rb")

class Admin::SiteCustomization::CardsController

  private

    alias_method :consul_card_params, :card_params

    def card_params
      # First, get the standard permitted attributes from the original method
      permitted_attributes = consul_card_params

      # Then, check our custom dropdown's value
      new_cardable_param = params.require(:widget_card).permit(:new_cardable_id)[:new_cardable_id]

      if new_cardable_param.present?
        if new_cardable_param == "homepage_nil"
          # This is the crucial part:
          # If "Homepage" was selected, forcefully set the parent attributes to nil,
          # overriding any defaults that might have been set.
          permitted_attributes[:cardable_type] = nil
          permitted_attributes[:cardable_id] = nil
        else
          # Otherwise, parse the selection as usual
          type, id = new_cardable_param.split('_')
          permitted_attributes[:cardable_type] = type
          permitted_attributes[:cardable_id] = id
        end
      end

      # Return the final, corrected hash of attributes
      permitted_attributes
    end
end