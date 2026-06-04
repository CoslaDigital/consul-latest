class Layout::LoginItemsComponent < ApplicationComponent; end

;

load Rails.root.join("app", "components", "layout", "login_items_component.rb")

class Layout::LoginItemsComponent < ApplicationComponent
  attr_reader :user
  delegate :layout_menu_link_to, to: :helpers

  def initialize(user)
    @user = user
  end

  private

    def show_my_activity_link?
      !Rails.application.multitenancy_management_mode?
    end
end
