class AddKindToBudgets < ActiveRecord::Migration[7.0]
  def change
    add_column :budgets, :kind, :string, null: false, default: "budget"
  end
end
