# 1. Load the original controller file from the Consul application
load Rails.root.join("app", "controllers", "admin", "widget", "cards_controller.rb")

# 2. Re-open the controller's class to add our customization
class Admin::Widget::CardsController

  private

    # 3. Create a backup (alias) of the original `card_params` method
    alias_method :consul_card_params, :card_params

    # 4. Redefine the `card_params` method with our new logic
    def card_params
      # First, call the original method to get all the standard permitted attributes
      permitted_attributes = consul_card_params

      # Manually permit and retrieve our custom virtual attribute from the raw params
      new_cardable_param = params.require(:widget_card).permit(:new_cardable_id)[:new_cardable_id]

      # If our custom attribute is present, parse it and merge the real attributes
      # into the hash that the original method prepared for us.
      if new_cardable_param.present?
        type, id = new_cardable_param.split('_')
        permitted_attributes[:cardable_type] = type
        permitted_attributes[:cardable_id] = id
      end

      # Return the final, modified hash
      permitted_attributes
    end
end