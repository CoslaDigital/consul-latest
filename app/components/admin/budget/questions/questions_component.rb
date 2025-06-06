class Admin::Budget::Questions::QuestionsComponent < ApplicationComponent
    include Header
    attr_reader :budget
  
    def initialize(budget)
      @budget = budget
    end
  
    private
      def enabled_cell(phase)
        render Admin::BudgetPhases::ToggleEnabledComponent.new(phase)
      end  
  end
  