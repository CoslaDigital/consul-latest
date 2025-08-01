class Admin::BudgetQuestions::FormComponent < ApplicationComponent
  # Include the same helpers you use for your Polls form component if they are relevant
  # for handling translatable fields and Globalize.
  include TranslatableFormHelper # If you have this for `translatable_form_for`
  include GlobalizeHelper # If you use this for locale rendering, etc.

  attr_reader :budget_question, :budget, :form_url

  # Parameters:
  # - budget_question: The Budget::Question instance (new or existing).
  # - budget: The parent Budget instance (for context, e.g., if needed for select options or display).
  # - form_url: The URL the form should submit to.
  def initialize(budget_question:, budget:, form_url:)
    @budget_question = budget_question
    @budget = budget
    @form_url = form_url
  end

  private

  # Helper to format the 'options' array (if it exists) for display in a textarea.
    def options_value_for_textarea
      budget_question.options&.join("\n")
    end
end
