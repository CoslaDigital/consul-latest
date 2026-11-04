load Rails.root.join("app", "models", "setting.rb")

class Setting
  class << self
    alias_method :consul_defaults, :defaults

    def defaults
      if Rails.env.test?
        consul_defaults
      else
        consul_defaults.merge({
                                # Overwrite default CONSUL DEMOCRACY settings or add new settings here
                                "feature.events": false,
                                "feature.offers": false,
                                "feature.hide_comments": false,
                                "feature.hide_votes": false,
                                "feature.hide_local_login": false,
                                "feature.demographics": false,
                                "feature.restrict_debate_creation": false,
                                "feature.restrict_login_to_officials": false,
                                "feature.require_login_to_view_processes": false,
                                "feature.user_milestones": false,
                                "feature.enable_card_login": false,
                                "feature.my_area_landing_page": false,

                                # Dynamic Verification Pipeline Settings
                                "verification.ys_requires_demographics": false,
                                "verification.require_residence": true,
                                "verification.require_sms": true,
                                "verification.require_letter": false
                              })
      end
    end

    def resources_visible?
      Setting["feature.resources"] == "active"
    end

    def hide_votes?
      Setting["feature.hide_votes"] == "active"
    end

    def hide_comments?
      Setting["feature.hide_comments"] == "active"
    end

    def hide_local_login?
      Setting["feature.hide_local_login"] == "active"
    end

    def restrict_debate_creation?
      Setting["feature.restrict_debate_creation"] == "active"
    end

    def can_edit_milestones?
      Setting["feature.user_milestones"] == "active"
    end

    def enable_card_login?
      Setting["feature.enable_card_login"] == "active"
    end

    def my_area_enabled?
      Setting["feature.my_area_landing_page"] == "active"
    end
  end
end
