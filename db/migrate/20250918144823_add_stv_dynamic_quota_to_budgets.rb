class AddStvDynamicQuotaToBudgets < ActiveRecord::Migration[7.0]
  def change
    add_column :budgets, :stv_dynamic_quota, :boolean
  end
end
