class AddVotesToInvestments < ActiveRecord::Migration[6.1]
  def change
    if column_exists?(:budget_investments, :votes)
      change_column :budget_investments, :votes, :numeric, precision: 10, scale: 2
    else
      add_column :budget_investments, :votes, :numeric, precision: 10, scale: 2
    end
  end
end
