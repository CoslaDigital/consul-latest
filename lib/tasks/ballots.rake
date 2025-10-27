namespace :ballots do
  desc "Backfill positions for existing ballot lines based on their creation order"
  task backfill_positions: :environment do
    puts "Starting to backfill positions for Budget::Ballot::Line..."

    # Group by the scopes defined in acts_as_list
    Budget::Ballot::Line.group(:ballot_id, :group_id).count.keys.each do |ballot_id, group_id|

      # Find all lines within this scope, ordered by their ID (or created_at)
      lines = Budget::Ballot::Line.where(ballot_id: ballot_id, group_id: group_id).order(id: :asc)

      # Loop through and set the position
      lines.each_with_index do |line, index|
        # Use update_column to skip validations and callbacks
        line.update_column(:position, index + 1)
      end
    end

    puts "Backfill complete!"
  end
end