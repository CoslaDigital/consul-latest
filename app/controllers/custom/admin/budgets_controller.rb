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

  def index
    # --- MANUAL DEBUGGING CODE ---
    Rails.logger.debug "--- CanCanCan Debug in BudgetsController#index ---"
    Rails.logger.debug "Current User: #{current_user.inspect}"
    Rails.logger.debug "Ability Class being used: #{current_ability.class.name}"

    # 1. Manual Authorization Step
    # This will raise the CanCan::AccessDenied error if it fails,
    # pinpointing the exact moment of failure.
    #    authorize! :index, Budget

    # 2. Manual Loading Step
    # This shows you the collection of budgets the user is allowed to see.
    #    @budgets = Budget.accessible_by(current_ability)
    #    Rails.logger.debug "Accessible Budgets Found: #{@budgets.count}"
    #    Rails.logger.debug "------------------------------------------------"
    @budgets = Budget.send(@current_filter).order(created_at: :desc).page(params[:page])
  end

  def show
  end

  def edit
  end

  def publish
    @budget.publish!
    redirect_to admin_budget_path(@budget), notice: t("admin.budgets.publish.notice")
  end

  def calculate_winners
    if @budget.stv
      @budget.headings.each { |heading| Budget::Stvresult.new(@budget, heading, user: current_user).delay.calculate_stv_winners }
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

  def stv_report_pdf
    @budget = Budget.find_by_slug_or_id!(params[:id])
    @heading = @budget.headings.find(params[:heading_id]) # Assumes heading_id is passed

    # --- Re-run the STV data gathering process ---
    seats = @budget.stv_winners
    votes_cast = @budget.ballots.count
    @candidates = @heading.investments.where(budget_id: @budget.id, selected: true)
    @quota = Budget::Stvresult.new(@budget, @heading).droop_quota(votes_cast, seats)

    ballot_data = Budget::Stvresult.new(@budget, @heading).get_votes_data
    @investment_titles = @candidates.pluck(:id, :title).to_h

    calculator = ::StvCalculator.new
    @result = calculator.calculate(ballot_data, seats, @quota, @investment_titles)
    # --- End of data gathering ---

    render pdf: "stv_report_#{@budget.slug}", # This sets the downloaded file's name
           template: "budgets/results/stv_report_pdf", # The new template we'll create
           layout: "pdf" # A specific layout for PDFs
  end

  private

    alias_method :consul_allowed_params, :allowed_params

    def allowed_params
      consul_allowed_params + [:stv, :stv_winners, :stv_dynamic_quota, :kind]
    end

end
