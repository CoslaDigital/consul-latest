class AddStvToBudget < ActiveRecord::Migration[6.1]
  def change
    add_column :budgets, :stv, :boolean unless column_exists?(:budgets, :stv)
    add_column :budgets, :stv_winners, :integer unless column_exists?(:budgets, :stv_winners)
  end
end