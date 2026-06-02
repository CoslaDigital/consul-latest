class AddDefaultToProposalKinds < ActiveRecord::Migration[7.2]
  def change
    add_column :proposal_kinds, :default, :boolean, default: false, null: false
  end
end
