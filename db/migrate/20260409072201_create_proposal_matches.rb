class CreateProposalMatches < ActiveRecord::Migration[7.2]
  def change
    create_table :proposal_matches do |t|
      # The two sides of the match
      t.references :proposal, null: false, foreign_key: true
      t.references :offer, null: false, foreign_key: true

      # State machine status (0: pending, 10: accepted, etc.)
      t.integer :status, default: 0, null: false

      # Lifecycle timestamps
      t.datetime :accepted_at
      t.datetime :completed_at
      t.timestamps
    end
    # Prevent duplicate requests between the same proposal and offer
    add_index :proposal_matches, [:proposal_id, :offer_id], unique: true
    add_index :proposal_matches, :status
  end
end
