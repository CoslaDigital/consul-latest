class AddSummaryToBudgetInvestmentTranslations < ActiveRecord::Migration[8.0]
  def change
    add_column :budget_investment_translations, :summary, :text
  end
end
