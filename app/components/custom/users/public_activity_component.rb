class Users::PublicActivityComponent < ApplicationComponent; end

load Rails.root.join("app", "components", "users", "public_activity_component.rb")

class Users::PublicActivityComponent

  def valid_filters
    @valid_filters ||= [
      ("proposals" if feature?(:proposals)),
      ("debates" if feature?(:debates)),
      ("budget_investments" if feature?(:budgets)),
      ("offers" if feature?(:offers)),
      "comments",
      ("follows" if valid_interests_access?(user))
    ].compact.select { |filter| send(filter).any? }
  end

  def offers
    user.offers
  end
end
