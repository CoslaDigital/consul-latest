class Budgets::Investments::FormComponent < ApplicationComponent; end

load Rails.root.join("app", "components", "budgets", "investments","form_component.rb")

class Budgets::Investments::FormComponent
  include TranslatableFormHelper
  include GlobalizeHelper
  attr_reader :investment, :url
  delegate :current_user, :budget_heading_select_options, :suggest_data, to: :helpers

  def initialize(investment, url:)
    @investment = investment
    @url = url
  end

  private

    def budget
      investment.budget
    end

    def categories
      Tag.category.order(:name)
    end
end
