class BudgetsController < ApplicationController
  include FeatureFlags
  include BudgetsHelper

  feature_flag :budgets

  before_action :load_budget, only: :show
  before_action :load_current_budget, only: :index
  load_and_authorize_resource

  respond_to :html, :js

  def show
    raise ActionController::RoutingError, "Not Found" unless budget_published?(@budget)
  end

  def index
    # 1. Start with only published budgets (just to be safe)
    published_budgets = @budgets.published

    # 2. Extract the finished budgets for the bottom section
    @finished_budgets = published_budgets.finished.order(created_at: :desc)

    # 3. Redefine @budgets to be everything published EXCEPT the finished ones
    @budgets = published_budgets.where.not(id: @finished_budgets.select(:id)).order(created_at: :desc)
  end

  def select
    @proposal = Proposal.find(params[:proposal_id])
    @budgets = Budget.accepting
  end

  def select_headings
    @proposal = Proposal.find(params[:proposal_id])
    @budget = Budget.find(params[:budget_id])
    @groups = Budget::Group.where(budget_id: @budget.id)
  end

  def budget_headings
    @group = Budget::Group.find(params[:group_id])
    @headings = @group.headings
    respond_to do |format|
      format.json { render json: @headings }
    end
  end

  private

    def load_budget
      @budget = Budget.find_by_slug_or_id! params[:id]
    end

    def load_current_budget
      @budget = current_budget
    end
end
