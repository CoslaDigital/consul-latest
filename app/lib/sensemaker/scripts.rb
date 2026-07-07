# frozen_string_literal: true

module Sensemaker
  module Scripts
    SCRIPTS = %w[
      health_check
      categorize
      bridge_scores
      report_text
      propositions
      refine_propositions
      ranked_propositions
      report_ui
    ].freeze

    PUBLISHABLE_SCRIPTS = %w[report_ui].freeze

    PIPELINE_SCRIPTS = %w[categorize bridge_scores report_text].freeze

    PROPOSITION_PIPELINE_SCRIPTS = %w[propositions refine_propositions ranked_propositions].freeze

    CLI_COMMANDS = {
      "health_check" => "sensemaking-health-check",
      "categorize" => "sensemaking-categorize",
      "bridge_scores" => "sensemaking-bridge-scores",
      "report_text" => "sensemaking-report-text",
      "propositions" => "sensemaking-propositions",
      "refine_propositions" => "sensemaking-refine-propositions",
      "ranked_propositions" => "sensemaking-world-model",
      "report_ui" => "sensemaking-report"
    }.freeze

    PRIMARY_OUTPUT_BASENAMES = {
      "health_check" => "health-check.txt",
      "categorize" => "categorized_without_other_filtered.csv",
      "bridge_scores" => "bridging_scores.csv",
      "report_text" => "report_data.json",
      "propositions" => "world_model.pkl",
      "refine_propositions" => "refined_world_model.pkl",
      "ranked_propositions" => "final_propositions_by_topic.csv",
      "report_ui" => "report.html"
    }.freeze

    SECONDARY_OUTPUT_BASENAMES = {
      "report_text" => ["report_data_with_opinions.json"]
    }.freeze

    def self.cli_for(script)
      CLI_COMMANDS.fetch(script) do
        raise ArgumentError, "Unknown Sensemaker script: #{script}"
      end
    end

    def self.primary_output_basename(script)
      PRIMARY_OUTPUT_BASENAMES.fetch(script) do
        raise ArgumentError, "Unknown Sensemaker script: #{script}"
      end
    end

    def self.secondary_output_basenames(script)
      SECONDARY_OUTPUT_BASENAMES[script] || []
    end

    def self.human_name_for(script)
      script.to_s.tr("_", " ").titleize
    end
  end
end
