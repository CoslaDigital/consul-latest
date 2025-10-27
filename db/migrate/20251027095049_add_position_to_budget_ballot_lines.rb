class AddPositionToBudgetBallotLines < ActiveRecord::Migration[7.0]
  def change
    add_column :budget_ballot_lines, :position, :integer
  end
end
