# db/seeds/stv_stress_test.rb

puts "🚀 Initializing STV Statutory Stress Test..."

ActiveRecord::Base.transaction do
  # 1. Create a generic author to assign to the investments
  author = User.find_or_create_by!(email: "stv_author@example.com") do |u|
    u.password = "password123"
    u.username = "stv_author"
    u.confirmed_at = Time.current
    u.terms_of_service = '1'
  end

  # 2. Create the Election (Budget)
  budget = Budget.create!(
    name: "2026 Local Elections (Statutory Stress Test)",
    phase: "finished", # Ensure it's in a phase where results can be calculated
    currency_symbol: "£"
  )

  # Standard Consul Budgets require a Group
  group = Budget::Group.create!(
    name: "Main Constituency Group",
    budget: budget
  )

  # 3. Create the Constituency (Heading)
  heading = Budget::Heading.create!(
    name: "Constituency C (Stress Test)",
    group: group,
    price: 1000000,
    max_winners: 3 # 3 Seats to fill
  )

  # 4. Create the 5 Candidates (Investments)
  puts "👥 Creating 5 Candidates..."
  candidates = {}
  ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo'].each do |name|
    candidates[name] = Budget::Investment.create!(
      title: name,
      description: "Candidate manifesto for #{name}.",
      author: author,
      budget: budget,
      heading: heading,
      selected: true, # CRITICAL: STV Engine only looks at selected candidates
      feasibility: "feasible",
      price: 10000
    )
  end

  # 5. Helper method to create voters and ordered STV ballots
  def cast_stv_ballot(budget, heading, candidate_sequence)
    # Create a unique voter
    voter = User.create!(
      email: "voter_#{SecureRandom.hex(6)}@example.com",
      password: "password123",
      username: "voter_#{SecureRandom.hex(4)}",
      confirmed_at: Time.current,
      terms_of_service: '1'
    )

    # Create the physical ballot container
    ballot = Budget::Ballot.create!(
      user: voter,
      budget: budget,
      physical: false
    )

    # Create the individual preference lines with strict positional ranking
    candidate_sequence.each_with_index do |candidate, index|
      Budget::Ballot::Line.create!(
        ballot: ballot,
        investment: candidate,
        heading: heading,
        position: index + 1 # CRITICAL: This is the 1st, 2nd, 3rd preference order!
      )
    end
  end

  # 6. Cast the exact 26 ballots required to trigger the edge cases
  puts "🗳️ Casting 26 targeted STV Ballots..."

  # 10 Ballots: [Alpha -> Delta -> Charlie] (Triggers Alpha's Surplus Transfer)
  10.times { cast_stv_ballot(budget, heading, [candidates['Alpha'], candidates['Delta'], candidates['Charlie']]) }

  # 6 Ballots: [Charlie]
  6.times { cast_stv_ballot(budget, heading, [candidates['Charlie']]) }

  # 5 Ballots: [Bravo] (Triggers the Zero-Surplus bug fix in Round 3)
  5.times { cast_stv_ballot(budget, heading, [candidates['Bravo']]) }

  # 3 Ballots: [Delta -> Charlie] (Sets up the Statutory Tie-Breaker in Round 4)
  3.times { cast_stv_ballot(budget, heading, [candidates['Delta'], candidates['Charlie']]) }

  # 2 Ballots: [Echo -> Bravo] (Sets up the first elimination transfer)
  2.times { cast_stv_ballot(budget, heading, [candidates['Echo'], candidates['Bravo']]) }

  puts "✅ Election Seed Complete!"
  puts "---------------------------------------------------"
  puts "Budget ID:  #{budget.id}"
  puts "Heading ID: #{heading.id}"
  puts "---------------------------------------------------"
  puts "You can now run @heading.calculate_stv_winners in the console!"
end
