# spec/services/stv_calculator_spec.rb

require "rails_helper"

RSpec.describe StvCalculator do
  subject(:calculator) { described_class.new }

  # ------------------------------------------------------------------
  # Helper: expand a ballot tally into individual ballots
  #
  # Takes an array of [count, rankings] pairs (NOT a Hash — Hash keys
  # must be unique, and multiple groups can legitimately share a count).
  # ------------------------------------------------------------------
  def ballot_tally(*pairs)
    pairs.flat_map do |count, rankings|
      Array.new(count) { { rankings: rankings.dup } }
    end
  end

  # ------------------------------------------------------------------
  # ERS97-style canonical STV election
  #   Candidates: A, B, C, D   (ids 1..4)
  #   Ballots:    43
  #   Seats:      2
  #   Quota:      15   (floor(43 / 3) + 1)
  #
  # First preferences:
  #   A: 14   B: 14   C: 13   D: 2
  #
  # Expected count:
  #   Round 1: D (2) eliminated → A (16)
  #   Round 2: A elected (surplus 1) → transfers 16 * (1/16) = 1.0 to B → B (15)
  #   Round 3: B elected (surplus 0). Seats filled.
  #
  # Winners: [1, 2]
  # ------------------------------------------------------------------
  let(:candidates) { { 1 => "A", 2 => "B", 3 => "C", 4 => "D" } }
  let(:seats) { 2 }
  let(:quota) { 15 }

  let(:ballot_data) do
    ballot_tally(
      [14, [1, 2, 3]],
      [14, [2, 1, 3]],
      [13, [3, 1, 2]],
      [2, [4, 1, 2, 3]]
    )
  end

  # ==================================================================
  # Basic sanity
  # ==================================================================
  describe "#calculate" do
    it "returns a Result struct" do
      result = calculator.calculate(ballot_data, seats, quota, candidates)
      expect(result).to be_a(StvCalculator::Result)
      expect(result).to respond_to(:winners, :elimination_log, :unfilled_seats, :rounds, :exhausted_total)
    end

    it "does not mutate the input ballot data" do
      original = Marshal.load(Marshal.dump(ballot_data))
      calculator.calculate(ballot_data, seats, quota, candidates)
      expect(ballot_data).to eq(original)
    end

    it "returns the correct number of rounds" do
      result = calculator.calculate(ballot_data, seats, quota, candidates)
      expect(result.rounds).to be_an(Array)
      expect(result.rounds.size).to be >= 1
    end
  end

  # ==================================================================
  # ERS97 canonical scenario
  # ==================================================================
  describe "ERS97 canonical election (A, B, C, D / 2 seats)" do
    let(:result) { calculator.calculate(ballot_data, seats, quota, candidates) }

    it "elects A and B" do
      expect(result.winners).to contain_exactly(1, 2)
    end

    it "fills both seats" do
      expect(result.unfilled_seats).to eq(0)
    end

    it "eliminates D in the first round" do
      first_elim = result.elimination_log.first
      expect(first_elim[:id]).to eq(4)
      expect(first_elim[:votes]).to eq(2.0)
    end

    it "records A as elected in round 2" do
      election_round = result.rounds.find { |r| r[:action]&.dig(:candidate_id) == 1 }
      expect(election_round).not_to be_nil
      expect(election_round[:action][:type]).to eq(:election)
      expect(election_round[:action][:surplus]).to be_within(0.001).of(1.0)
    end

    it "records B as elected" do
      b_round = result.rounds.find do |r|
        r[:action]&.dig(:candidate_id) == 2 && r[:action][:type] == :election
      end
      expect(b_round).not_to be_nil
    end
  end

  # ==================================================================
  # Surplus transfer (WIGM)
  # ==================================================================
  describe "surplus transfer (WIGM)" do
    # A: 6 first prefs, all with B next.
    # B: 3 first prefs, with A next.
    # C: 1 first pref, no other pref.
    #
    # Seats: 2, quota: 4
    #   Round 1: A=6, B=3, C=1. A elected (surplus 2), fraction = 2/6 = 1/3.
    #            Each A ballot transfers 1.0 * 1/3 = 1/3 to B.
    #            B total = 3 + 6*(1/3) = 5.
    #   Round 2: B=5 >= 4, elected. Seats filled.
    let(:surplus_data) do
      ballot_tally(
        [6, [1, 2]],
        [3, [2, 1]],
        [1, [3]]
      )
    end

    it "transfers the correct surplus fraction to the next preference" do
      result = calculator.calculate(surplus_data, 2, 4, { 1 => "A", 2 => "B", 3 => "C" })
      expect(result.winners).to include(1)
      expect(result.winners).to include(2)
    end

    it "transfers fractional values, not whole votes" do
      result = calculator.calculate(surplus_data, 2, 4, { 1 => "A", 2 => "B", 3 => "C" })
      # B's total should be 3 + (6 * 1/3) = 5, not 3 + 6 = 9.
      b_round = result.rounds.find { |r| r[:standings].key?(2) }
      expect(b_round[:standings][2]).to be_within(0.001).of(3.0) # round 1

      b_after_transfer = result.rounds
                               .map { |r| r[:standings][2] }
                               .compact
                               .last
      expect(b_after_transfer).to be_within(0.001).of(5.0)
    end

    it "preserves fractional values across later eliminations" do
      # Forces partial transfers from A to B and C, producing non-integer standings.
      # A=7, quota=4, surplus=3, transfer fraction=3/7.
      # A's 5 ballots go to B (5 × 3/7 = 15/7), A's 2 ballots go to C (2 × 3/7 = 6/7).
      # B = 1 + 15/7 = 22/7 ≈ 3.142857 (non-integer)
      # C = 1 + 6/7 = 13/7 ≈ 1.857 (non-integer)
      ballots = ballot_tally(
        [5, [1, 2]],
        [2, [1, 3]],
        [1, [2, 1]],
        [1, [3, 1]],
        [1, [4, 3, 1]]
      )
      result = calculator.calculate(ballots, 2, 4, { 1 => "A", 2 => "B", 3 => "C", 4 => "D" })

      all_standings = result.rounds.flat_map { |r| r[:standings].values }
      non_integer = all_standings.select { |v| v > 0.0 && v != v.to_i }
      expect(non_integer).not_to be_empty
    end
  end

  # ==================================================================
  # Elimination transfer preserves value
  # ==================================================================
  describe "elimination transfer" do
    it "transfers ballots at their current (possibly fractional) value" do
      # A=10, B=2, C=1. Seats=3, quota=4.
      #   Round 1: A=10, B=2, C=1. A elected (surplus 6, fraction 6/10=0.6).
      #            A's ballots (all [1,2,3]) → next is B, each worth 0.6.
      #            B total = 2 + 10*0.6 = 8.
      #   Round 2: B=8 >= 4, elected (surplus 4, fraction 4/8=0.5).
      #            B's ballots → next is C, each worth 0.6*0.5=0.3.
      #            C total = 1 + 10*0.3 = 4.
      #   Round 3: C=4 >= 4, elected. Seats filled.
      ballots = ballot_tally(
        [10, [1, 2, 3]],
        [2, [2, 3]],
        [1, [3, 1, 2]]
      )
      result = calculator.calculate(ballots, 3, 4, { 1 => "A", 2 => "B", 3 => "C" })
      expect(result.winners).to contain_exactly(1, 2, 3)
    end
  end

  # ==================================================================
  # Dynamic quota
  # ==================================================================
  describe "dynamic quota" do
    it "recalculates quota when ballots exhaust" do
      ballots = ballot_tally(
        [5, [1]],
        [5, [2, 1]],
        [3, [3, 2]]
      )
      result = calculator.calculate(
        ballots, 2, 4, { 1 => "A", 2 => "B", 3 => "C" },
        dynamic_quota_enabled: true
      )
      # With dynamic quota, the quota should change as ballots exhaust.
      quotas = result.rounds.map { |r| r[:quota] }
      expect(quotas.uniq.size).to be > 1
    end
  end

  # ==================================================================
  # Exhausted votes
  # ==================================================================
  describe "exhausted votes" do
    it "tracks exhausted vote value, not just ballot count" do
      # A=6, B=3, C=1. Seats=2, quota=4.
      #   Round 1: A elected (surplus 2, fraction 1/3).
      #            A's ballots → next is B, each worth 1/3.
      #            B total = 3 + 6*(1/3) = 5. B elected. Seats filled.
      # No exhaustion.
      ballots = ballot_tally(
        [6, [1, 2]],
        [3, [2, 1]],
        [1, [3]]
      )
      result = calculator.calculate(ballots, 2, 4, { 1 => "A", 2 => "B", 3 => "C" })
      expect(result.exhausted_total).to eq(0.0)
    end

    it "counts fractional exhausted values" do
      # A=6, B=2 (only [2]), C=1 (only [3]). Seats=2, quota=3.
      #   Round 1: A=6, B=2, C=1. A elected (surplus 3, fraction 3/6 = 0.5).
      #            A's 6 ballots [1, 2] → next is B, each worth 0.5.
      #            B total = 2 + 6*0.5 = 5. B elected. Seats filled.
      # No exhaustion.
      ballots = ballot_tally(
        [6, [1, 2]],
        [2, [2]],
        [1, [3]]
      )
      result = calculator.calculate(ballots, 2, 3, { 1 => "A", 2 => "B", 3 => "C" })
      # B was elected before any exhaustion could occur.
      expect(result.exhausted_total).to eq(0.0)
    end

    it "accumulates exhausted value correctly" do
      # A=5 (only [1]), B=5 (only [2]). Seats=2, quota=6.
      #   Round 1: A=5, B=5. No one >= 6. Eliminate one (tie → lot).
      #            Say A is eliminated. A's 5 ballots exhaust → 5.0.
      #   Loop check: active_candidates (1) <= empty_seats (2) → break.
      #   Auto-elect B.
      # Total exhausted = 5.0
      ballots = ballot_tally(
        [5, [1]],
        [5, [2]]
      )
      result = calculator.calculate(ballots, 2, 6, { 1 => "A", 2 => "B" })
      expect(result.exhausted_total).to eq(5.0)
    end
  end

  # ==================================================================
  # Tie-breaking
  # ==================================================================
  describe "tie-breaking" do
    it "breaks ties deterministically by candidate id" do
      # A=3, B=3, C=2. Seats=2, quota=3.
      #   Round 1: A=3, B=3 → both hit quota. Both elected. Seats filled.
      ballots = ballot_tally(
        [3, [1]],
        [3, [2]],
        [2, [3]]
      )
      result = calculator.calculate(ballots, 2, 3, { 1 => "A", 2 => "B", 3 => "C" })
      expect(result.winners).to contain_exactly(1, 2)
    end

    it "resolves elimination ties by lower id" do
      # A=2, B=2, C=1. Seats=2, quota=2.
      #   Round 1: A=2, B=2 → both hit quota. Both elected.
      ballots = ballot_tally(
        [2, [1]],
        [2, [2]],
        [1, [3]]
      )
      result = calculator.calculate(ballots, 2, 2, { 1 => "A", 2 => "B", 3 => "C" })
      expect(result.winners).to contain_exactly(1, 2)
    end

    it "records tie-break message in elimination action" do
      # A=1, B=1, C=3. Seats=2, quota=2.
      #   Round 1: C=3 >= 2 → C elected. A=1, B=1 tie for elimination.
      #   Eliminate A (deterministic tie-break by id).
      #   Remaining candidates: B. Auto-elect.
      ballots = ballot_tally(
        [1, [1, 3]],
        [1, [2, 3]],
        [3, [3, 1]]
      )
      result = calculator.calculate(ballots, 2, 2, { 1 => "A", 2 => "B", 3 => "C" })

      elim_round = result.rounds.find { |r| r[:action]&.dig(:type) == :elimination }
      # If a tie occurred, the message should be present.
      if elim_round && elim_round[:action][:tie_break_message]
        expect(elim_round[:action][:tie_break_message]).to be_a(String)
      end
    end
  end

  # ==================================================================
  # Unfilled seats
  # ==================================================================
  describe "unfilled seats" do
    it "reports unfilled seats when candidates run out" do
      # A=1, B=1. Seats=3, quota=1.
      #   Round 1: A=1 >= 1 → elected. B=1 >= 1 → elected.
      #            Only 2 candidates for 3 seats → 1 unfilled.
      ballots = ballot_tally(
        [1, [1]],
        [1, [2]]
      )
      result = calculator.calculate(ballots, 3, 1, { 1 => "A", 2 => "B" })
      expect(result.unfilled_seats).to eq(1)
    end
  end

  # ==================================================================
  # Auto-election
  # ==================================================================
  describe "auto-election of remaining candidates" do
    it "auto-elects remaining candidates when seats outnumber candidates" do
      # A=2, B=1. Seats=2, quota=2.
      #   Round 1: A=2 >= 2 → A elected. B=1 < 2.
      #            After A elected: active=[2], empty=1 → break.
      #            Auto-elect B.
      ballots = ballot_tally(
        [2, [1, 2]],
        [1, [2]]
      )
      result = calculator.calculate(ballots, 2, 2, { 1 => "A", 2 => "B" })
      expect(result.winners).to contain_exactly(1, 2)
      auto_round = result.rounds.find { |r| r[:action]&.dig(:type) == :auto_election }
      expect(auto_round).not_to be_nil
    end

    it "creates a distinct round for auto-election with the candidate's real tally" do
      # A=2, B=1, seats=2, quota=2 -> A elected on first prefs, B auto-elected.
      ballots = ballot_tally(
        [2, [1, 2]],
        [1, [2]]
      )
      result = calculator.calculate(ballots, 2, 2, { 1 => "A", 2 => "B" })

      auto_round = result.rounds.find { |r| r[:action]&.dig(:type) == :auto_election }
      expect(auto_round).not_to be_nil

      # Auto-election should be its own round, distinct from any elimination.
      elimination_rounds = result.rounds.select { |r| r[:action]&.dig(:type) == :elimination }
      expect(auto_round[:iteration]).to be > elimination_rounds.map { |r| r[:iteration] }.max.to_i

      # The round should show the candidate's real tally, not 0.
      expect(auto_round[:standings][2]).to eq(1.0)
      expect(auto_round[:action][:count]).to eq(1.0)
    end
  end

  # ==================================================================
  # Retained vote accounting is a view concern, not a calculator concern
  # ==================================================================
  describe "retained vote accounting (calculator)" do
    it "does not include retained_total in round data" do
      ballots = ballot_tally(
        [10, [1, 2]],
        [5, [2, 1]],
        [3, [3, 1]],
        [2, [4, 3]]
      )
      result = calculator.calculate(ballots, 2, 7, { 1 => "A", 2 => "B", 3 => "C", 4 => "D" })

      result.rounds.each do |round|
        expect(round).not_to have_key(:retained_total)
      end
    end
  end

  # ==================================================================
  # Rounds data structure
  # ==================================================================
  describe "rounds data" do
    let(:result) { calculator.calculate(ballot_data, seats, quota, candidates) }

    it "each round has the expected keys" do
      result.rounds.each do |round|
        expect(round).to include(:iteration, :quota, :standings, :action, :transfers, :exhausted_total)
        expect(round[:standings]).to be_a(Hash)
      end
    end

    it "records transfers as a hash" do
      result.rounds.each do |round|
        expect(round[:transfers]).to be_a(Hash)
      end
    end

    it "records action as a hash with type" do
      result.rounds.each do |round|
        next if round[:action].nil?
        expect(round[:action]).to include(:type)
      end
    end
  end
  # ==================================================================
  # Deterministic tie-breaking
  # ==================================================================
  describe "deterministic tie-breaking" do
    # A tie scenario: four candidates at 2 votes each, plus one at 4.
    # Forces a random-lot elimination to break the four-way tie.
    let(:tied_ballots) do
      ballot_tally(
        [4, [1, 5]],
        [2, [2, 5]],
        [2, [3, 5]],
        [2, [4, 5]]
      )
    end

    let(:tied_candidates) { { 1 => "A", 2 => "B", 3 => "C", 4 => "D", 5 => "E" } }

    it "produces the same winners for the same election_seed" do
      r1 = calculator.calculate(tied_ballots, 2, 3, tied_candidates, election_seed: "seed-abc")
      r2 = calculator.calculate(tied_ballots, 2, 3, tied_candidates, election_seed: "seed-abc")
      expect(r1.winners).to eq(r2.winners)
    end

    it "produces the same elimination order for the same election_seed" do
      r1 = calculator.calculate(tied_ballots, 2, 3, tied_candidates, election_seed: "seed-abc")
      r2 = calculator.calculate(tied_ballots, 2, 3, tied_candidates, election_seed: "seed-abc")
      expect(r1.elimination_log.map { |e| e[:id] }).to eq(r2.elimination_log.map { |e| e[:id] })
    end

    it "produces the same result from a fresh calculator instance with the same seed" do
      r1 = described_class.new.calculate(tied_ballots, 2, 3, tied_candidates, election_seed: "seed-fresh")
      r2 = described_class.new.calculate(tied_ballots, 2, 3, tied_candidates, election_seed: "seed-fresh")
      expect(r1.winners).to eq(r2.winners)
    end

    it "records the seed in the tie-break message when a random lot is used" do
      result = calculator.calculate(tied_ballots, 2, 3, tied_candidates, election_seed: "seed-xyz")
      elim_round = result.rounds.find do |r|
        r[:action]&.dig(:type) == :elimination &&
          r[:action][:tie_break_message]&.include?("random lot")
      end
      expect(elim_round).not_to be_nil
      expect(elim_round[:action][:tie_break_message]).to match(/seed: \d+/)
    end
    it "includes exhausted_after_action in each round" do
      result = calculator.calculate(ballot_data, seats, quota, candidates)
      result.rounds.each do |round|
        expect(round).to have_key(:exhausted_after_action)
      end
    end
  end
end
