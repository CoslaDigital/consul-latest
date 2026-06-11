# lib/tasks/proposals.rake
namespace :proposals do
  desc "Initialize default proposal kinds in the database"
  task initialize_kinds: :environment do
    defaults = ["Citizen Proposal", "Mutual Aid", "Capital Infrastructure"]

    puts "Checking and initializing default proposal kinds..."

    defaults.each do |kind_name|
      # find_or_create_by ensures running this multiple times won't create duplicates
      kind = ProposalKind.find_or_create_by!(name: kind_name)
      puts " -> Verified record: #{kind.name} (ID: #{kind.id})"
    end

    if ProposalKind.any? && !ProposalKind.exists?(default: true)
      ProposalKind.first.update!(default: true)
    end

    puts "Proposal kinds initialization complete!"
  end
end
