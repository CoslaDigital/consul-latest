# app/controllers/milestones_controller.rb

class MilestonesController < ApplicationController
  # This finds the parent budget and investment from the URL
  before_action :set_budget_and_investment

  # CanCanCan will automatically load and authorize @milestone
  # using the @investment parent object we find above.
  load_and_authorize_resource :milestone, through: :investment

  # This is good to keep if your forms need a list of statuses
  before_action :load_statuses, only: [:new, :create, :edit, :update]

  def new
    # @milestone is built automatically by load_and_authorize_resource
  end

  def create
    # @milestone is built automatically with the correct params
    if @milestone.save
      redirect_to budget_investment_path(@budget, @investment), notice: "Milestone successfully created."
    else
      render :new
    end
  end

  def edit
    # @milestone is loaded automatically
  end

  def update
    # @milestone is loaded automatically
    if @milestone.update(milestone_params)
      redirect_to budget_investment_path(@budget, @investment), notice: "Milestone successfully updated."
    else
      render :edit
    end
  end

  def destroy
    @milestone.destroy
    redirect_to budget_investment_path(@budget, @investment), notice: "Milestone successfully deleted."
  end

  private

  def set_budget_and_investment
    @budget = Budget.find(params[:budget_id])
    @investment = @budget.investments.find(params[:investment_id])
  end

  def load_statuses
    # This is an example; adjust if your Status model is different
    @statuses = Milestone::Status.all if defined?(Milestone::Status)
  end

  def milestone_params
    # Make sure this permit list matches your form fields
    #params.require(:milestone).permit(:title, :description, :due_date, :status_id) # Use status_id if it's an association
    params.require(:milestone).permit(
    :status_id,
    :publication_date,
    translations_attributes: [:id, :locale, :title, :description],
    image_attributes: [:id, :cached_attachment, :title, :user_id, :_destroy],
    documents_attributes: [:id, :cached_attachment, :title, :user_id, :_destroy]
  )
  end
end