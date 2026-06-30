class AddRejectedAtToProposalMatches < ActiveRecord::Migration[7.2]
  def change
    add_column :proposal_matches, :rejected_at, :datetime
  end
end
