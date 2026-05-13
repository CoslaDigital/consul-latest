class Budgets::FooterComponent < ApplicationComponent; end
load Rails.root.join("app", "components", "budgets", "footer_component.rb")
class Budgets::FooterComponent < ApplicationComponent
  delegate :custom_t, to: :helpers
end
