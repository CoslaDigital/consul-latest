# frozen_string_literal: true

require "rails_helper"

describe SensemakerExt::ScriptRegistryPatch do
  before do
    SensemakerExt::Loader.install!
  end

  describe "proposition pipeline scripts" do
    it "maps CLI commands for each proposition script" do
      expect(Sensemaker::ScriptRegistry.python_cli_for("propositions"))
        .to eq("sensemaking-propositions")
      expect(Sensemaker::ScriptRegistry.python_cli_for("refine_propositions"))
        .to eq("sensemaking-refine-propositions")
      expect(Sensemaker::ScriptRegistry.python_cli_for("ranked_propositions"))
        .to eq("sensemaking-world-model")
    end

    it "wires nested prep_steps" do
      expect(Sensemaker::ScriptRegistry.prep_steps("propositions")).to eq(["categorize"])
      expect(Sensemaker::ScriptRegistry.prep_steps("refine_propositions")).to eq(["propositions"])
      expect(Sensemaker::ScriptRegistry.prep_steps("ranked_propositions"))
        .to eq(["refine_propositions"])
    end

    it "marks ranked_propositions as not requiring an LLM" do
      expect(Sensemaker::ScriptRegistry.requires_llm?("propositions")).to be true
      expect(Sensemaker::ScriptRegistry.requires_llm?("refine_propositions")).to be true
      expect(Sensemaker::ScriptRegistry.requires_llm?("ranked_propositions")).to be false
    end

    it "maps refine_propositions to fast and primary stage model flags" do
      expect(Sensemaker::ScriptRegistry.model_flags("refine_propositions")).to eq(
        [
          { role: :fast, flag: "--simulated_jury_model_name" },
          { role: :primary, flag: "--nuanced_propositions_model_name" }
        ]
      )
    end

    it "defaults propositions to primary --model_name" do
      expect(Sensemaker::ScriptRegistry.model_flags("propositions")).to eq(
        [{ role: :primary, flag: "--model_name" }]
      )
    end

    it "returns no model flags when the script does not require an LLM" do
      expect(Sensemaker::ScriptRegistry.model_flags("ranked_propositions")).to eq([])
    end

    it "marks report_ui as not requiring an LLM" do
      expect(Sensemaker::ScriptRegistry.requires_llm?("report_ui")).to be false
    end

    it "exposes all three as user-selectable Python scripts" do
      expect(Sensemaker::ScriptRegistry.user_selectable).to include(
        "propositions",
        "refine_propositions",
        "ranked_propositions"
      )
    end

    it "returns primary artefact basenames" do
      job = build(:sensemaker_job, id: 7)

      expect(Sensemaker::ScriptRegistry.artefact_config("propositions")[:output_basename].call(job))
        .to eq("world_model.pkl")
      expect(
        Sensemaker::ScriptRegistry.artefact_config("refine_propositions")[:output_basename].call(job)
      ).to eq("refined_world_model.pkl")
      expect(
        Sensemaker::ScriptRegistry.artefact_config("ranked_propositions")[:output_basename].call(job)
      ).to eq("final_propositions_by_topic.csv")
    end
  end
end
