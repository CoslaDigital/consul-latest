class AddProposalKindToProposals < ActiveRecord::Migration[7.2]
  def change
    add_reference :proposals, :proposal_kind, null: true, foreign_key: true
  end
end
