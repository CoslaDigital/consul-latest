class Admin::BudgetQuestions::RowComponent < ApplicationComponent
  attr_reader :question

  def initialize(question)
    
    @question = question
    @budget = budget
  end

  private

    def budget
      question.budget
    end

    def question_path
      admin_budget_budget_question_path(budget_id: budget.id,
                                          id: question.id,
                                          params: Budget::Investment.filter_params(params).to_h)
    end

    def administrator_info
      if question.administrator.present?
        tag.span(question.administrator.description_or_name,
                 title: t("admin.budget_questions.index.assigned_admin"))
      else
        t("admin.budget_questions.index.no_admin_assigned")
      end
    end

    def valuators_info
      valuators = [question.assigned_valuation_groups, question.assigned_valuators].compact

      if valuators.present?
        valuators.join(", ")
      else
        t("admin.budget_questions.index.no_valuators_assigned")
      end
    end
end