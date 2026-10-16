load Rails.root.join("app", "controllers", "admin", "budget_investments_controller.rb")

class Admin::BudgetInvestmentsController < Admin::BaseController
  include ImageAttributes

  # Ensure all budget questions have an associated answer object built for the form
  before_action :build_custom_question_answers, only: [:edit]

  private

    alias_method :consul_allowed_params, :allowed_params

    def allowed_params
      consul_allowed_params + [
        :winner,
        :budget_question_id,
        answers_attributes: [:id, :text, :budget_id, :budget_question_id]
      ]
    end

    def build_custom_question_answers
      return unless @budget && @investment

      # Ensure an answer record exists in memory for every active budget question
      @budget.questions.order(:id).each do |question|
        @investment.answers.find_or_initialize_by(
          budget_question: question,
          budget: @budget
        )
      end
    end
end
