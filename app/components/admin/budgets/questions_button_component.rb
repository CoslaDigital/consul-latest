# app/components/admin/budgets/questions_button_component.rb
class Admin::Budgets::QuestionsButtonComponent < ApplicationComponent
  attr_reader :budget

#  use_helpers :can?

  def initialize(budget) 
    @budget = budget
  end

  def render?
 #   path.present? #&& can?(:manage_questions, @budget) # Define :manage_questions ability in your Ability file
  end

  private

  # Provides the text for the button/link.
  # Sourced from locale files for I18n.
  def text
    t("admin.budgets.questions_button_component.text", default: "Manage Questions")
  end

  # Provides the URL path for the button/link.
  # This directs to the page where questions for the budget can be managed.
  def path
    helpers.admin_budget_budget_questions_path(@budget)
  rescue ActionController::UrlGenerationError
    # Gracefully handle cases where the route might not be defined (e.g., during development or if modules are disabled)
    nil
  end

  # Provides any specific CSS classes for the button/link.
  # You can customize this as needed.
  def html_class
    "button hollow float-right clear" 
  end
end