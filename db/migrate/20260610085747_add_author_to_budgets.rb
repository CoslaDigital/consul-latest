class AddAuthorToBudgets < ActiveRecord::Migration[7.2]
  def change
    add_column :budgets, :author_id, :integer
    add_index :budgets, :author_id
  end
end
