class CreateBulkPasswordResets < ActiveRecord::Migration[7.0] # Use your Rails version
  def change
    create_table :bulk_password_resets do |t|
      t.references :admin_user, foreign_key: { to_table: :users }
      t.string :status, default: "processing"
      t.integer :target_count, default: 0
      t.integer :success_count, default: 0

      t.timestamps
    end
  end
end
