class Budgets::Investments::CategoriesComponent < ApplicationComponent
  attr_reader :budget, :heading, :current_search

  def initialize(budget:, heading:, search:)
    @budget = budget
    @heading = heading
    @current_search = search
  end

  def investments_scope
    scope = budget.investments
    scope = scope.where(heading_id: heading.id) if heading
    scope.select(:id)
  end

  def call
    render Shared::CategoriesComponent.new(
      taggable_type: "Budget::Investment",
      taggable_ids: investments_scope,
      current_search: current_search,
      url_method: :budget_investments_path,
      url_params: { budget_id: budget.id, heading_id: heading&.id }
    )
  end
end
