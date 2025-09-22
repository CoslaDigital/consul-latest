class  Admin::Budgets::FormComponent < ApplicationComponent; end

load Rails.root.join("app", "components", "admin", "budgets", "form_component.rb")
class Admin::Budgets::FormComponent < ApplicationComponent
  include TranslatableFormHelper
  include GlobalizeHelper
  include Admin::Namespace

  attr_reader :budget, :wizard
  alias_method :wizard?, :wizard
  
  VOTING_STYLES = {
    "budget"   => [["Knapsack", "knapsack"], ["Approval", "approval"]],
    "election" => [["Approval (for STV)", "approval"]]
  }.freeze
  
  def initialize(budget, wizard: false)
    @budget = budget
    @wizard = wizard
  end
  
  def voting_styles_for_js
    VOTING_STYLES.to_json
  end
    
   def kind_select_options
    Budget.kinds.keys.map do |kind|
      [kind.humanize, kind]
    end
  end

  def voting_styles_select_options
    VOTING_STYLES[budget.kind] || []    
  end

  def currency_symbol_select_options
    Budget::CURRENCY_SYMBOLS.map { |cs| [cs, cs] }
  end

  def phases_select_options
    Budget::Phase::PHASE_KINDS.map { |ph| [t("budgets.phase.#{ph}"), ph] }
  end

  private

    def admins
      @admins ||= Administrator.includes(:user)
    end

    def valuators
      @valuators ||= Valuator.includes(:user).order(description: :asc).order("users.email ASC")
    end

    def hide_money_style
      "hide" if budget.voting_style == "knapsack"
    end
end
