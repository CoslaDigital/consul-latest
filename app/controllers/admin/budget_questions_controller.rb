# app/controllers/admin/budget_questions_controller.rb
class Admin::BudgetQuestionsController < Admin::BaseController # Or ApplicationController, or your admin base
 include Translatable
  include ReportAttributes
  before_action :set_budget
  before_action :set_budget_question, only: [:show, :edit, :update, :destroy, :mark_as_enabled, :unmark_as_enabled]

  # GET /admin/budgets/:budget_id/budget_questions
  def index
#    @budget.inspect
    @budget_questions = @budget.questions#.compact
  end

  # GET /admin/budgets/:budget_id/budget_questions/:id
  def show
  end

  # GET /admin/budgets/:budget_id/budget_questions/new
  def new
    @budget_question = @budget.questions.new
  end

  # POST /admin/budgets/:budget_id/budget_questions
  def create
    @budget_question = @budget.questions.new(budget_question_params)
    if @budget_question.save
      redirect_to admin_budget_budget_questions_path(@budget), notice: t(".success", name: @budget_question.text.truncate(30))
    else
      flash.now[:alert] = t(".failure")
      render :new, status: :unprocessable_entity
    end
  end

  # GET /admin/budgets/:budget_id/budget_questions/:id/edit
  def edit
  end

  # PATCH/PUT /admin/budgets/:budget_id/budget_questions/:id
  def update
    permitted_params = budget_question_params

    if @budget_question.update(budget_question_params)
      redirect_to admin_budget_budget_questions_path(@budget), notice: t(".success", name: @budget_question.text.truncate(30))
    else
      flash.now[:alert] = t(".failure")
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /admin/budgets/:budget_id/budget_questions/:id
  def destroy
    question_text = @budget_question.text.truncate(30)
    @budget_question.destroy
    redirect_to admin_budget_budget_questions_path(@budget), notice: t(".success", name: question_text), status: :see_other
  end
  
  def mark_as_enabled
    @budget_question.update!(enabled: true)

    respond_to do |format|
      format.html { redirect_to request.referer, notice: t("flash.actions.update.budget_investment") }
      format.js { render :toggle_enabled }
    end
  end

  def unmark_as_enabled
    @budget_question.update!(enabled: false)

    respond_to do |format|
      format.html { redirect_to request.referer, notice: t("flash.actions.update.budget_investment") }
      format.js { render :toggle_enabled }
    end
  end
  
  private

  def set_budget
    @budget = Budget.find(params[:budget_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_budgets_path, alert: t("admin.budgets.not_found") # Or a more appropriate fallback
  end

  def set_budget_question
    @budget_question = @budget.questions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_budget.questions_path(@budget), alert: t(".not_found")
  end
  
  def budget_question_params
    # Adjust the permitted attributes based on your BudgetQuestion model's actual fields.
    params.require(:budget_question).permit(
      *allowed_params
    )
  end

  def allowed_params
    valid_attributes = [
      :text,
      :enabled,
      :hint, # Optional hint/description for the question
      :mandatory
    ]
    [*valid_attributes, translation_params(Budget::Question)]
  end

end
