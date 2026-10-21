# spec/models/budget/stv_result_spec.rb

require "rails_helper"

RSpec.describe Budget::StvResult, type: :model do
  describe "#to_calculator_result" do
    it "round-trips a simple election through the database" do
      budget = create(:budget)
      heading = create(:budget_heading, budget: budget)
      calc = StvCalculator.new

      ballots = [
        { rankings: [1, 2] },
        { rankings: [1, 2] },
        { rankings: [2, 1] }
      ]

      result = calc.calculate(ballots, 1, 2, { 1 => "A", 2 => "B" }, election_seed: "test")

      row = described_class.record!(
        budget: budget,
        heading: heading,
        result: result,
        seats: 1,
        quota: 2,
        votes_cast: ballots.size,
        election_seed: "test",
        dynamic_quota_enabled: false,
        investment_titles: { 1 => "A", 2 => "B" }
      )

      restored = row.to_calculator_result

      expect(restored.winners).to eq(result.winners)
      expect(restored.rounds.size).to eq(result.rounds.size)
      expect(restored.rounds[0][:action][:type]).to be_a(Symbol)
      expect(restored.rounds[0][:standings].keys).to all(be_a(Integer))
      expect(row.investment_titles_for_display.keys).to all(be_a(Integer))
    end
  end
end
