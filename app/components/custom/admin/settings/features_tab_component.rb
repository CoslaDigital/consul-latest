load Rails.root.join("app", "components", "admin", "settings", "features_tab_component.rb")

class Admin::Settings::FeaturesTabComponent < ApplicationComponent
  alias_method :original_settings, :settings

  def settings
    custom_settings = %w[ feature.offers
                          feature.demographics
                          feature.hide_local_login
                          feature.hide_comments
                          feature.hide_votes
                          feature.restrict_debate_creation
                          feature.user_milestones
                          feature.restrict_login_to_officials
                          feature.require_login_to_view_processes
                          feature.enable_card_login
                          feature.my_area_landing_page
                          verification.ys_requires_demographics
                          verification.require_residence
                          verification.require_sms
                          verification.require_letter
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
