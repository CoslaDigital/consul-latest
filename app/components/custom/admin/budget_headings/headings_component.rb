# 1. Pre-declare to bind the view to the custom folder
class Admin::BudgetHeadings::HeadingsComponent < ApplicationComponent; end

# 2. Load the original core component
load Rails.root.join("app", "components", "admin", "budget_headings", "headings_component.rb")

# 3. Re-open (empty because we don't need to change any Ruby logic here)
class Admin::BudgetHeadings::HeadingsComponent
end
