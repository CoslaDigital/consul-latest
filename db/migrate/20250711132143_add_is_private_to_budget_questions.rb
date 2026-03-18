class AddIsPrivateToBudgetQuestions < ActiveRecord::Migration[7.0]
  def change
    add_column :budget_questions, :is_private, :boolean, default: false
  end
end
