class AddQuestionsToBudgets < ActiveRecord::Migration[5.2]
  def change
    unless table_exists?(:budget_questions)
    create_table :budget_questions do |t|
      t.references :budget
      t.boolean :enabled, default: true
    end
  end  
  end
end
