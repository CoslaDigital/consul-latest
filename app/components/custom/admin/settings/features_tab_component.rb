load Rails.root.join("app","components","admin","settings","features_tab_component.rb")

class Admin::Settings::FeaturesTabComponent < ApplicationComponent
  alias_method :original_settings, :settings

  def settings
    custom_settings = %w[ feature.demographics
                          feature.hide_local_login
                          feature.hide_comments
                          feature.hide_votes
                          feature.restrict_debate_creation
                        ]
    original_settings + custom_settings
  end
end
