load Rails.root.join("app", "components", "admin", "settings", "features_tab_component.rb")

class Admin::Settings::FeaturesTabComponent < ApplicationComponent
  alias_method :original_settings, :settings

  def initialize
    super # (If inheriting from a component that requires super)

    # 1. Force SMS toggle OFF in the database if the API key is missing
    # This prevents the toggle from being "stuck ON and greyed out"
    if Tenant.current_secrets&.sms_api_key.blank? && Setting["verification.require_sms"].present?
      Setting["verification.require_sms"] = nil
    end
  end

  def settings
    custom_settings = %w[ feature.demographics
                          feature.hide_local_login
                          feature.hide_comments
                          feature.hide_votes
                          feature.restrict_debate_creation
                          feature.user_milestones
                          feature.restrict_login_to_officials
                          feature.require_login_to_view_processes
                          feature.enable_card_login
                          verification.ys_requires_demographics
                          verification.require_email_confirmation
                          verification.require_residence
                          verification.require_sms
                          verification.require_letter
                          feature.my_area_landing_page
                          feature.geofence_card_login
                        ]
    original_settings + custom_settings
  end

  def setting_disabled?(key)
    if key == "verification.require_sms"
      Tenant.current_secrets&.sms_api_key.blank?
    else
      false # All other settings remain enabled by default
    end
  end
end
