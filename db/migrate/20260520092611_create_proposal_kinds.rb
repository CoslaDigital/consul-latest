class CreateProposalKinds < ActiveRecord::Migration[7.2]
  def change
    create_table :proposal_kinds do |t|
      t.string :name
      t.string :slug

      t.timestamps
    end
  end
end
