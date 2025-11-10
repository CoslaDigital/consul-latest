class Budgets::SubheaderComponent < ApplicationComponent; end

load Rails.root.join("app","components","budgets","subheader_component.rb")
class Budgets::SubheaderComponent < ApplicationComponent
  use_helpers :current_user, :link_to_signin, :link_to_signup, :link_to_verify_account, :can?, :custom_t
  attr_reader :budget

  def initialize(budget)
    @budget = budget
  end
end
