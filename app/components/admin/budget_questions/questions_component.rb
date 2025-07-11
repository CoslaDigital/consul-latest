class Admin::BudgetQuestions::QuestionsComponent < ApplicationComponent
  attr_reader :budget, :budget_questions

  def initialize(budget, budget_questions)
    @budget = budget
    @budget_questions = budget_questions
  end

  private

    def cookie
      "budget_questions-columns-#{budget.current_phase.kind}"
    end

end