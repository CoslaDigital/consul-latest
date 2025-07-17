class Admin::Budgets::ActionsComponent < ApplicationComponent; end

load Rails.root.join("app","components","admin","budgets","actions_component.rb")

class Admin::Budgets::ActionsComponent < ApplicationComponent
  attr_reader :budget

  def initialize(budget)
    @budget = budget
  end

  private

    def action(action_name, **)
      render Admin::ActionComponent.new(action_name, budget, "aria-describedby": true, **)
    end

    def actions
      @actions ||= {
        calculate_winners: {
          hint: winners_hint,
          html: winners_action
        },
        ballots: {
          hint: ballots_hint,
          html: ballots_action
        },
        questions: {
          hint: questions_hint,
          html: questions_action
        },
        destroy: {
          hint: destroy_hint,
          html: destroy_action
        }
      }.select { |_, button| button[:html].present? }
    end

    def questions_hint
      t("admin.budgets.actions.descriptions.questions")
    end
    
    def questions_action
      action(:questions,
         path: admin_budget_budget_questions_path(budget),
         text: t("admin.budgets.actions.questions", default: "Manage Questions"),
         class: "button expanded")
    end

    def descriptor_id(action_name)
      "#{dom_id(budget, action_name)}_descriptor"
    end
end
