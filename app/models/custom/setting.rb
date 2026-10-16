load Rails.root.join("app", "models", "setting.rb")

class Setting
  GEOFENCE_ENABLED_KEY = "rack_attack:geofence_enabled".freeze
  GEOFENCE_COUNTRIES_KEY = "rack_attack:allowed_countries".freeze

  after_save :clear_rack_attack_geofence_cache

  class << self
    alias_method :consul_defaults, :defaults

    # Change this code when you'd like to add settings that aren't
    # already present in the database. These settings will be added when
    # first installing CONSUL DEMOCRACY, when deploying code with Capistrano,
    # or when manually executing the `settings:add_new_settings` task.
    #
    # If a setting already exists in the database, changing its value in
    # this file will have no effect unless the task `rake db:seed` is
    # invoked or the method `Setting.reset_defaults` is executed. Doing
    # so will overwrite the values of all existing settings in the
    # database, so use with care.
    #
    # The tests in the spec/ folder rely on CONSUL DEMOCRACY's default
    # settings, so it's recommended not to change the default settings
    # in the test environment.
    def defaults
      if Rails.env.test?
        consul_defaults
      else
        consul_defaults.merge({
                                # Overwrite default CONSUL DEMOCRACY settings or add new settings here
                                "feature.events": false,
                                "feature.hide_comments": false,
                                "feature.hide_votes": false,
                                "feature.hide_local_login": false,
                                "feature.demographics": false,
                                "feature.restrict_debate_creation": false,
                                "feature.user_milestones": false,
                                "feature.restrict_login_to_officials": false,
                                "feature.require_login_to_view_processes": false,
                                "feature.enable_card_login": false,
                                "feature.my_area_landing_page": false,
                                "feature.geofence_card_login": true,
                                "geofence_allowed_countries": "GB"
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

    # Returns true if geofencing is switched on in the admin dashboard
    def geofence_card_login_enabled?
      Rails.cache.fetch(GEOFENCE_ENABLED_KEY, expires_in: 2.minutes) do
        # Checks for "active" (saved in DB by Consul admin UI) or boolean true/string "true"
        Setting["feature.geofence_card_login"].to_s.in?(["active", "true"])
      end
    rescue StandardError => e
      Rails.logger.warn("Failed reading geofence setting: #{e.message}")
      true # Fails safe (closed) on error
    end

    # Returns array of allowed ISO codes, e.g. ["GB", "IM", "JE"]
    def geofence_allowed_countries
      Rails.cache.fetch(GEOFENCE_COUNTRIES_KEY, expires_in: 2.minutes) do
        raw = Setting["geofence_allowed_countries"]

        # Fallback to Tenant secrets or credentials if database entry is blank
        if raw.blank? && defined?(Tenant) && Tenant.respond_to?(:current_secrets)
          raw = Tenant.current_secrets&.dig(:geofence, :allowed_countries)
        end

        raw = "GB" if raw.blank?
        raw.to_s.split(",").map(&:strip).map(&:upcase).reject(&:blank?)
      end
    rescue StandardError => e
      Rails.logger.warn("Failed reading allowed countries setting: #{e.message}")
      ["GB"]
    end
  end

  private

    def clear_rack_attack_geofence_cache
      if key.in?(["feature.geofence_card_login", "geofence_allowed_countries"])
        Rails.cache.delete(GEOFENCE_ENABLED_KEY)
        Rails.cache.delete(GEOFENCE_COUNTRIES_KEY)
      end
    end
end
