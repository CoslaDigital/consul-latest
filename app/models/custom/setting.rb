load Rails.root.join("app", "models", "setting.rb")

class Setting
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
          "feature.saml_login": true,
          "feature.valid_geozone": true,
          "moderation.vendor": true,
          "moderation.comments": "",
          "moderation.images": true,
          "moderation.proposals": true,
          "moderation.threshold_low": 0.8,
          "moderation.threshold_high": 2.0,
          "moderation.threshold": 1.5,
          "feature.hide_local_login": false

        })
      end
    end
    

    def moderate_comments?
      Setting["moderation.comments"].present?
    end

     def moderate_proposals?
      Setting["moderation.proposals"].present?
    end

    def get_vendor_name
      vendor_key = Setting["moderation.vendor"]
      vendor = Llm::Vendor.find_by(id: vendor_key)
      vendor.name if vendor
    end

    def get_vendor_api
      vendor_key = Setting["moderation.vendor"]
      vendor = Llm::Vendor.find_by(id: vendor_key)
      vendor.api_key if vendor
    end

    def hide_local_login?
      Setting["feature.hide_local_login"] == "active"
    end

  end
end
