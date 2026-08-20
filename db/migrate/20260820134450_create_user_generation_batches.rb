class CreateUserGenerationBatches < ActiveRecord::Migration[7.0] # Your Rails version
  def change
    create_table :user_generation_batches do |t|
      t.references :admin_user, foreign_key: { to_table: :users }
      t.string :status, default: "processing"
      t.integer :target_count, default: 0
      t.integer :success_count, default: 0

      t.timestamps
    end
  end
end
