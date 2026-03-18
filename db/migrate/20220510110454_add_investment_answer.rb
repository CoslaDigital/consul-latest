class AddInvestmentAnswer < ActiveRecord::Migration[5.2]
  def change
    unless table_exists?(:budget_investment_answers)
    create_table :budget_investment_answers do |t|
      t.references :budget
      t.references :investment
      t.references :budget_question
      t.string :text, null: false
    end
  end
  end
end
