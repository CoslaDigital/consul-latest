class Admin::BudgetQuestions::ToggleEnabledComponent < ApplicationComponent
  attr_reader :question
  use_helpers :can?
  delegate :enabled?, to: :question

  def initialize(question)
    @question = question
  end

  private

    def selected_text
      t("admin.budget_investments.index.selected")
    end

    def action
      if enabled?
        :unmark_as_enabled
      else
        :mark_as_enabled
      end
    end

    def path
      url_for({
        controller: "admin/budget_questions",
        action: action,
        budget_id: question.budget,
        id: question,
        filter: params[:filter],
        sort_by: params[:sort_by],
        min_total_supports: params[:min_total_supports],
        max_total_supports: params[:max_total_supports],
        advanced_filters: params[:advanced_filters],
        page: params[:page]
      })
    end

    def options
      {
        "aria-label": label,
        form_class: "toggle-enabled",
        path: path
      }
    end

    def label
      t("admin.actions.label", action: t("admin.actions.select"), name: question.text.truncate(30))
    end
end