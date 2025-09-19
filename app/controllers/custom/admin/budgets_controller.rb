load Rails.root.join("app", "controllers", "admin", "budgets_controller.rb")

class Admin::BudgetsController < Admin::BaseController
  include Translatable
  include ReportAttributes
  include ImageAttributes
  include FeatureFlags
  feature_flag :budgets

  has_filters %w[all open finished], only: :index

  before_action :load_budget, except: [:index]
  load_and_authorize_resource class: "Budget"


  def calculate_winners
    if @budget.stv
      @budget.headings.each { |heading| Budget::Stvresult.new(@budget, heading).delay.calculate_stv_winners }
    else
      @budget.headings.each { |heading| Budget::Result.new(@budget, heading).delay.calculate_winners }
    end

    #@budget.headings.each { |heading| Budget::Result.new(@budget, heading).delay.calculate_winners }
    redirect_to admin_budget_budget_investments_path(
                  budget_id: @budget.id,
                  advanced_filters: ["winners"]
                ),
                notice: I18n.t("admin.budgets.winners.calculated")
  end


  private

    alias_method :consul_allowed_params, :allowed_params
        
    def allowed_params
      consul_allowed_params + [:stv, :stv_winners, :stv_dynamic_quota]
    end

end
