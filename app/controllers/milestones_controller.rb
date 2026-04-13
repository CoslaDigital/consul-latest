class MilestonesController < ApplicationController
  # Make these available to your views for back links and forms
  helper_method :milestoneable_path, :milestoneable

  # 1. Detect the parent (Proposal or Investment)
  before_action :load_milestoneable

  # 2. Use CanCanCan to load the milestone THROUGH the detected parent
  load_and_authorize_resource :milestone, through: :milestoneable

  # 3. Ensure route variables (@budget, @investment) exist for nested path helpers
  before_action :set_route_variables, only: [:new, :create, :edit, :update]
  before_action :load_statuses, only: [:new, :create, :edit, :update]

  def new
    # @milestone is built automatically by load_and_authorize_resource
  end

  def create
    if @milestone.save
      redirect_to milestoneable_path, notice: t("milestones.create.notice", default: "Milestone successfully created.")
    else
      render :new
    end
  end

  def edit
    # @milestone is loaded automatically
  end

  def update
    if @milestone.update(milestone_params)
      redirect_to milestoneable_path, notice: t("milestones.update.notice", default: "Milestone successfully updated.")
    else
      render :edit
    end
  end

  def destroy
    @milestone.destroy
    redirect_to milestoneable_path, notice: t("milestones.delete.notice", default: "Milestone successfully deleted.")
  end

  # Generic path helper that handles different nesting levels
  def milestoneable_path
    if @milestoneable.is_a?(Budget::Investment)
      budget_investment_path(@budget, @investment, anchor: "tab-milestones")
    else
      polymorphic_path(@milestoneable, anchor: "tab-milestones")
    end
  end

  private

    def load_milestoneable
      @milestoneable = milestoneable
      raise ActiveRecord::RecordNotFound if @milestoneable.nil?
    end

    def milestoneable
      # Polymorphic detector: finds the parent based on URL parameters
      if params[:investment_id]
        Budget::Investment.find(params[:investment_id])
      elsif params[:proposal_id]
        Proposal.find(params[:proposal_id])
      end
    end

    def set_route_variables
      # Hydrates @budget and @investment only if we are in a budget context
      # This prevents UrlGenerationErrors in the views/forms
      if @milestoneable.is_a?(Budget::Investment)
        @investment = @milestoneable
        @budget = @investment.budget

        # Verify the budget in the URL matches the investment's budget
        if params[:budget_id].present? && params[:budget_id].to_i != @budget.id
          raise ActiveRecord::RecordNotFound
        end
      end
    end

    def load_statuses
      @statuses = Milestone::Status.all if defined?(Milestone::Status)
    end

    def milestone_params
      params.require(:milestone).permit(
        :status_id,
        :publication_date,
        translations_attributes: [:id, :locale, :title, :description],
        image_attributes: [:id, :cached_attachment, :title, :user_id, :_destroy],
        documents_attributes: [:id, :cached_attachment, :title, :user_id, :_destroy]
      )
    end
end
