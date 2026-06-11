["Standard Project", "Mutual Aid", "Capital Infrastructure"].each do |kind_name|
  ProposalKind.find_or_create_by!(name: kind_name)
end
