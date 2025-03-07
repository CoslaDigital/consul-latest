module Admin
  module Settings
    class DropdownFormComponent < ViewComponent::Base
      def initialize(setting, collection:, value_method:, text_method:, tab: nil)
        @setting = setting
        @collection = collection
        @value_method = value_method
        @text_method = text_method
        @tab = tab
      end
    end
  end
end