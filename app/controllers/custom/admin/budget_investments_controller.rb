load Rails.root.join("app", "controllers", "admin", "budget_investments_controller.rb")
class Admin::BudgetInvestmentsController < Admin::BaseController
  include ImageAttributes
  
  private

    alias_method :consul_allowed_params, :allowed_params
    
    def allowed_params
      consul_allowed_params + [:winner,  :budget_question_id]
    end
    
end
