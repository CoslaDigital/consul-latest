load Rails.root.join("app", "components", "admin", "settings", "configuration_tab_component.rb")

class Admin::Settings::ConfigurationTabComponent < ApplicationComponent
  alias_method :original_settings, :settings

  def settings
    custom_settings = %w[ geofence_allowed_countries
                        ]
    original_settings + custom_settings
  end
end
