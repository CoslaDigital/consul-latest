class CreateProposalMatches < ActiveRecord::Migration[7.2]
  def change
    unless table_exists?(:proposal_matches)
      create_table :proposal_matches do |t|
        t.references :proposal, null: false, foreign_key: true
        t.references :offer, null: false, foreign_key: true

        t.integer :status, default: 0, null: false

        t.datetime :accepted_at
        t.datetime :confirmed_at
        t.datetime :completed_at

        t.timestamps
      end
    end

    # Add columns if they were missed in previous iterations
    add_column :proposal_matches, :confirmed_at, :datetime unless column_exists?(:proposal_matches, :confirmed_at)

    # Index safety
    unless index_exists?(:proposal_matches, [:proposal_id, :offer_id])
      add_index :proposal_matches, [:proposal_id, :offer_id], unique: true
    end
    add_index :proposal_matches, :status unless index_exists?(:proposal_matches, :status)
  end
end
