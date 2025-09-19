module Budgets
  class ResultsController < ApplicationController
    before_action :load_budget
    before_action :load_heading

    authorize_resource :budget

    def show
      authorize! :read_results, @budget
      @investments = Budget::Result.new(@budget, @heading).investments
      @headings = @budget.headings.sort_by_name
      if @budget.stv?
       @summary_slug = "stv_results_#{@budget.name}_#{@heading.name}".downcase.tr(' ', '-')
       @detail_slug  = "stv_details_#{@budget.name}_#{@heading.name}".downcase.tr(' ', '-')
      end
    end

    private

      def load_budget
        @budget = Budget.find_by_slug_or_id(params[:budget_id]) || Budget.first
      end

      def load_heading
        if @budget.present?
          headings = @budget.headings
          @heading = headings.find_by_slug_or_id(params[:heading_id]) || headings.first
        end
      end
  end
end
