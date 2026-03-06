# app/components/admin/users/table_actions_component.rb
class Admin::Users::TableActionsComponent < ApplicationComponent
  attr_reader :user

  def initialize(user)
    @user = user
  end

  private

    def lockable?
      User.devise_modules.include?(:lockable)
    end

    def locked?
      user.access_locked?
    end

    def lock_icon_class
      locked? ? "locked-icon" : "unlocked-icon"
    end

    def lock_label
      locked? ? t("admin.users.account.locked") : t("admin.users.account.unlocked")
    end
end
