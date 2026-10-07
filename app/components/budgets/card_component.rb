class Budgets::CardComponent < ApplicationComponent
  attr_reader :budget

  def initialize(budget)
    @budget = budget
  end

  def image_url
    if budget.image.present? && budget.image.attachment.attached?
      helpers.url_for(budget.image.attachment)
    else
      # Use Consul's native helper to find the default image!
      helpers.image_path_for("budget_investment_no_image.jpg")
    end
  end
end
