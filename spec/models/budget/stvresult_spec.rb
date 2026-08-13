# spec/models/budget/stvresult_spec.rb

require 'rails_helper'

RSpec.describe Budget::Stvresult, type: :model do
  let(:author) do
    User.new(
      email: "author_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      username: "author_#{SecureRandom.hex(4)}",
      confirmed_at: Time.current,
      terms_of_service: '1'
    ).tap { |u| u.save!(validate: false) }
  end

  let(:admin) do
    User.new(
      email: "admin_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      username: "admin_#{SecureRandom.hex(4)}",
      confirmed_at: Time.current,
      terms_of_service: '1'
    ).tap { |u| u.save!(validate: false) }
  end

  let(:budget) do
    Budget.create!(
      name: "2026 Local Elections (RSpec Test)",
      phase: "finished",
      currency_symbol: "£"
    )
  end

  let(:group) do
    Budget::Group.create!(
      name: "Test Group",
      budget: budget
    )
  end

  let(:heading) do
    Budget::Heading.create!(
      name: "Test Constituency",
      group: group,
      price: 1000000,
      max_winners: 3
    )
  end

  let!(:candidates) do
    {
      'Alpha' => Budget::Investment.new(title: 'Alpha', description: 'Test', author: author, budget: budget, heading: heading, selected: true, feasibility: 'feasible', price: 1000).tap { |i| i.save!(validate: false) },
      'Bravo' => Budget::Investment.new(title: 'Bravo', description: 'Test', author: author, budget: budget, heading: heading, selected: true, feasibility: 'feasible', price: 1000).tap { |i| i.save!(validate: false) },
      'Charlie' => Budget::Investment.new(title: 'Charlie', description: 'Test', author: author, budget: budget, heading: heading, selected: true, feasibility: 'feasible', price: 1000).tap { |i| i.save!(validate: false) },
      'Delta' => Budget::Investment.new(title: 'Delta', description: 'Test', author: author, budget: budget, heading: heading, selected: true, feasibility: 'feasible', price: 1000).tap { |i| i.save!(validate: false) },
      'Echo' => Budget::Investment.new(title: 'Echo', description: 'Test', author: author, budget: budget, heading: heading, selected: true, feasibility: 'feasible', price: 1000).tap { |i| i.save!(validate: false) }
    }
  end

  def cast_ballot(candidate_sequence)
    voter = User.new(
      email: "voter_#{SecureRandom.hex(6)}@example.com",
      password: "password123",
      username: "voter_#{SecureRandom.hex(4)}",
      confirmed_at: Time.current,
      terms_of_service: '1'
    ).tap { |u| u.save!(validate: false) }

    ballot = Budget::Ballot.create!(
      user: voter,
      budget: budget,
      physical: false
    )

    candidate_sequence.each_with_index do |candidate, index|
      Budget::Ballot::Line.create!(
        ballot: ballot,
        investment: candidate,
        heading: heading,
        group: group, # Fixed: Added group validation reference
        position: index + 1
      )
    end
  end

  before do
    # Seed the 26 target ballots
    10.times { cast_ballot([candidates['Alpha'], candidates['Delta'], candidates['Charlie']]) }
    6.times { cast_ballot([candidates['Charlie']]) }
    5.times { cast_ballot([candidates['Bravo']]) }
    3.times { cast_ballot([candidates['Delta'], candidates['Charlie']]) }
    2.times { cast_ballot([candidates['Echo'], candidates['Bravo']]) }
  end

  describe "#calculate_stv_winners" do
    it "correctly computes the Droop Quota, WIGM surplus, tie-breaks, and winners" do
      engine = Budget::Stvresult.new(budget, heading, user: admin)
      winners = engine.calculate_stv_winners

      # Expect exactly 3 winners matching our stress test design: Alpha, Bravo, Charlie
      winner_titles = Budget::Investment.where(id: winners).pluck(:title).sort
      expect(winner_titles).to eq(['Alpha', 'Bravo', 'Charlie'])
    end
  end
end
