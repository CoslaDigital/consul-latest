require "rails_helper"

describe Sensemaker::Scripts do
  describe ".cli_for" do
    it "returns the sensemaking CLI command for categorize" do
      expect(Sensemaker::Scripts.cli_for("categorize")).to eq("sensemaking-categorize")
    end

    it "returns the sensemaking report CLI command for report_ui" do
      expect(Sensemaker::Scripts.cli_for("report_ui")).to eq("sensemaking-report")
    end

    it "returns the propositions CLI command for propositions" do
      expect(Sensemaker::Scripts.cli_for("propositions")).to eq("sensemaking-propositions")
    end

    it "returns the refine CLI command for refine_propositions" do
      expect(Sensemaker::Scripts.cli_for("refine_propositions")).to eq("sensemaking-refine-propositions")
    end

    it "returns the world model CLI command for ranked_propositions" do
      expect(Sensemaker::Scripts.cli_for("ranked_propositions")).to eq("sensemaking-world-model")
    end

    it "returns final_propositions_by_topic.csv for ranked_propositions" do
      expect(Sensemaker::Scripts.primary_output_basename("ranked_propositions"))
        .to eq("final_propositions_by_topic.csv")
    end

    it "returns world_model.pkl for propositions" do
      expect(Sensemaker::Scripts.primary_output_basename("propositions")).to eq("world_model.pkl")
    end

    it "returns refined_world_model.pkl for refine_propositions" do
      expect(Sensemaker::Scripts.primary_output_basename("refine_propositions"))
        .to eq("refined_world_model.pkl")
    end

    it "raises for unknown scripts" do
      expect do
        Sensemaker::Scripts.cli_for("runner.ts")
      end.to raise_error(ArgumentError, /Unknown Sensemaker script/)
    end
  end

  describe ".primary_output_basename" do
    it "returns report_data.json for report_text" do
      expect(Sensemaker::Scripts.primary_output_basename("report_text")).to eq("report_data.json")
    end
  end
end
