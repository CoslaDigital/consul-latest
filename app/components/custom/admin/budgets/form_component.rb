class Admin::Budgets::FormComponent < ApplicationComponent; end
require_dependency Rails.root.join("app", "components", "admin", "budgets", "form_component").to_s

class Admin::Budgets::FormComponent
  include TranslatableFormHelper
  include GlobalizeHelper
  include Admin::Namespace

  attr_reader :budget, :wizard
  alias_method :wizard?, :wizard

  def initialize(budget, wizard: false)
    @budget = budget
    @wizard = wizard
  end

  def voting_styles_select_options
    Budget::VOTING_STYLES.map do |style|
      [Budget.human_attribute_name("voting_style_#{style}"), style]
    end
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

    def hide_stv_style
      "hide" unless budget.voting_style == "stv"
    end

end
