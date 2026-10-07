class AddKindToBudgets < ActiveRecord::Migration[7.0]
  def change
    add_column :budgets, :kind, :string, null: false, default: "budget", if_not_exists: true
  end
end
