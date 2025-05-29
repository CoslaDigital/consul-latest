class Admin::Dashboard::IndexComponent < ApplicationComponent; end

load Rails.root.join("app", "components", "admin", "dashboard", "index_component.rb")
class Admin::Dashboard::IndexComponent < ApplicationComponent

  private

    def support_link
      mail_to "consul@cosla.gov.uk"
    end

    def documentation_link
      link_to "https://docs.consuldemocracy.org", "https://docs.consuldemocracy.org"
    end
end
