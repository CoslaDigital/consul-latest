class Admin::Budget::Questions::ToggleEnabledComponent < ApplicationComponent
  attr_reader :phase
  delegate :enabled?, to: :phase

  def initialize(question)
    @question = question
  end

  private

    def options
      { "aria-label": t("admin.budgets.edit.enable_question", question: question.text) }
    end

    def action
      if enabled?
        :disable
      else
        :enable
      end
    end
end
