class Investment
    class Budget::Investment::Answer < ApplicationRecord

      belongs_to :investment, touch: true
      belongs_to :budget_question, class_name: "Budget::Question"
        
    end
  end
  