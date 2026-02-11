class AddIsMandatoryAndHintToBudgetQuestions < ActiveRecord::Migration[7.0]
  def change
    add_column :budget_questions, :is_mandatory, :boolean
    add_column :budget_questions, :hint, :text
  end
end
