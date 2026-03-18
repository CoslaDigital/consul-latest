class AddInvestmentAnswerTranslations < ActiveRecord::Migration[5.2]
  def change
    unless table_exists?(:budget_investment_answer_translations)
    create_table :budget_investment_answer_translations do |t|
      t.integer :budget_investment_answer_id, null: false
      t.string :locale, null: false
      t.timestamps null: false
      t.text :text
    end
  end
  end
end
