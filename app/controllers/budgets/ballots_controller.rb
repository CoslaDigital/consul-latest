module Budgets
  class BallotsController < ApplicationController
    before_action :authenticate_user!
    before_action :load_budget
    authorize_resource :budget
    before_action :load_ballot

    def show
      authorize! :show, @ballot
      session[:ballot_referer] = request.referer
      render template: "budgets/ballot/show"
    end
    
    def reorder
    # Find the current user's ballot
    @budget = Budget.find(params[:budget_id])
    @ballot = @budget.ballots.find_by!(user: current_user) # Or however you find the user's ballot
    
    # Get the group_id from the params (we'll send this from the view)
    group_id = params[:group_id]

    # Use a transaction to ensure all updates succeed or fail together
    Budget::Ballot::Line.transaction do
      # params[:investment_ids] is the array of IDs from the JavaScript
      params[:investment_ids].each_with_index do |investment_id, index|
        
        # Find the specific line item for this user, group, and investment
        line = @ballot.lines.find_by(
          investment_id: investment_id,
          group_id: group_id
        )

        # Update its position (index is 0-based, position is 1-based)
        # We use update_column to be fast and skip validations
        line&.update_column(:position, index + 1)
      end
    end

    head :ok # Respond with "200 OK"
  end

    private

      def load_budget
        @budget = Budget.find_by_slug_or_id! params[:budget_id]
      end

      def load_ballot
        query = Budget::Ballot.where(user: current_user, budget: @budget)
        @ballot = @budget.balloting? ? query.first_or_create! : query.first_or_initialize
      end
  end
end
