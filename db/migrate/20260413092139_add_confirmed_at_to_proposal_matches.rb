class AddConfirmedAtToProposalMatches < ActiveRecord::Migration[7.2]
  def change
    add_column :proposal_matches, :confirmed_at, :datetime
  end
end
