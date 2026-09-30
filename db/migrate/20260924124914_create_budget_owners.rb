class CreateBudgetOwners < ActiveRecord::Migration[7.2]
  def change
    create_table :budget_owners do |t|
      t.references :budget, foreign_key: true
      t.references :user, foreign_key: true

      t.timestamps
    end
  end
end
