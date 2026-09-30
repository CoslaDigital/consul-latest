class AddMaxWinnersToBudgetHeadings < ActiveRecord::Migration[7.2]
  def change
    add_column :budget_headings, :max_winners, :integer
  end
end
