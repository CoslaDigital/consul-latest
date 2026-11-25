# frozen_string_literal: true

module SensemakerExt
  module ScriptRegistryPatch
    PYTHON_REGISTRY = {
      "health_check" => {
        backend: :python,
        logical_name: :health_check,
        publishable: false,
        internal: false,
        requires_input: false,
        prep_steps: [],
        i18n_key: "health_check",
        output_flag: :output_file,
        artefact_config: {
          output_basename: ->(_job) { "health-check.txt" },
          output_suffixes: [],
          default_input_path: nil,
          input_suffixes: []
        },
        cli_name: "sensemaking-health-check"
      },
      "categorize" => {
        backend: :python,
        logical_name: :categorize,
        publishable: false,
        internal: false,
        requires_input: true,
        prep_steps: [],
        i18n_key: "categorize",
        output_flag: :output_file,
        artefact_config: {
          # categorization_runner writes these under --output_dir (see tools README).
          output_basename: ->(_job) { "categorized" },
          output_suffixes: %w[
            _with_other.csv
            _with_other_filtered.csv
            _without_other.csv
            _without_other_filtered.csv
            _with_other_topic_tree.txt
          ],
          default_input_path: ->(job) {
            File.join(Sensemaker::Paths.job_directory(job), "input.csv")
          },
          input_suffixes: []
        },
        cli_name: "sensemaking-categorize"
      },
      "bridge_scores" => {
        backend: :python,
        logical_name: :advanced,
        publishable: false,
        internal: true,
        requires_input: true,
        prep_steps: ["categorize"],
        i18n_key: "bridge_scores",
        output_flag: :output_file,
        artefact_config: {
          output_basename: ->(_job) { "bridging_scores.csv" },
          output_suffixes: [],
          default_input_path: lambda { |job|
            File.join(
              Sensemaker::Paths.job_directory(job),
              "categorized_without_other_filtered.csv"
            )
          },
          input_suffixes: []
        },
        cli_name: "sensemaking-bridge-scores"
      },
      "report_text" => {
        backend: :python,
        logical_name: :summary,
        publishable: false,
        internal: false,
        requires_input: true,
        prep_steps: ["bridge_scores"],
        i18n_key: "report_text",
        output_flag: :output_file,
        artefact_config: {
          # generate_report_text writes both files under --output_dir (see tools README).
          output_basename: ->(_job) { "report_data" },
          output_suffixes: %w[.json _with_opinions.json],
          default_input_path: lambda { |job|
            File.join(Sensemaker::Paths.job_directory(job), "bridging_scores.csv")
          },
          input_suffixes: []
        },
        cli_name: "sensemaking-report-text"
      },
      "propositions" => {
        backend: :python,
        logical_name: :propositions,
        publishable: false,
        internal: false,
        requires_input: true,
        requires_llm: true,
        prep_steps: ["categorize"],
        i18n_key: "propositions",
        output_flag: :output_file,
        artefact_config: {
          output_basename: ->(_job) { "world_model.pkl" },
          output_suffixes: [],
          default_input_path: lambda { |job|
            File.join(Sensemaker::Paths.job_directory(job), "categorized")
          },
          input_suffixes: []
        },
        cli_name: "sensemaking-propositions"
      },
      "refine_propositions" => {
        backend: :python,
        logical_name: :refine_propositions,
        publishable: false,
        internal: false,
        requires_input: true,
        requires_llm: true,
        prep_steps: ["propositions"],
        i18n_key: "refine_propositions",
        output_flag: :output_file,
        artefact_config: {
          output_basename: ->(_job) { "refined_world_model.pkl" },
          output_suffixes: [],
          default_input_path: lambda { |job|
            File.join(Sensemaker::Paths.job_directory(job), "world_model.pkl")
          },
          input_suffixes: []
        },
        cli_name: "sensemaking-refine-propositions",
        model_flags: [
          { role: :fast, flag: "--simulated_jury_model_name" },
          { role: :primary, flag: "--nuanced_propositions_model_name" }
        ]
      },
      "ranked_propositions" => {
        backend: :python,
        logical_name: :ranked_propositions,
        publishable: false,
        internal: false,
        requires_input: true,
        requires_llm: false,
        prep_steps: ["refine_propositions"],
        i18n_key: "ranked_propositions",
        output_flag: :output_file,
        artefact_config: {
          output_basename: ->(_job) { "final_propositions_by_topic.csv" },
          output_suffixes: [],
          default_input_path: lambda { |job|
            File.join(Sensemaker::Paths.job_directory(job), "refined_world_model.pkl")
          },
          input_suffixes: []
        },
        cli_name: "sensemaking-world-model"
      },
      "report_ui" => {
        backend: :python,
        logical_name: :report,
        publishable: true,
        internal: false,
        requires_input: true,
        requires_llm: false,
        prep_steps: ["report_text"],
        i18n_key: "report_ui",
        output_flag: :output_file,
        config_schema_path: -> { SensemakerExt::Paths.report_builder_config_schema },
        artefact_config: {
          output_basename: ->(_job) { "report.html" },
          output_suffixes: [],
          default_input_path: lambda { |job|
            File.join(Sensemaker::Paths.job_directory(job), "report_data")
          },
          input_suffixes: %w[.json],
          additional_input_scripts: %w[bridge_scores]
        },
        cli_name: nil
      }
    }.freeze

    def all
      (super + PYTHON_REGISTRY.keys).uniq
    end

    def known?(script)
      python_config_for(script).present? || super
    end

    def for_backend(backend)
      return (super + PYTHON_REGISTRY.keys).uniq if backend.to_sym == :python

      super
    end

    def user_selectable
      python_user_selectable = PYTHON_REGISTRY.reject { |_id, config| config[:internal] }.keys
      (super + python_user_selectable).uniq
    end

    def publishable
      python_publishable = PYTHON_REGISTRY.select { |_id, config| config[:publishable] }.keys
      (super + python_publishable).uniq
    end

    def backend_for(script)
      python_config_for(script)&.fetch(:backend) || super
    end

    def logical_name(script)
      python_config_for(script)&.fetch(:logical_name) || super
    end

    def prep_steps(script)
      python_config_for(script)&.fetch(:prep_steps) || super
    end

    def i18n_key(script)
      python_config_for(script)&.fetch(:i18n_key) || super
    end

    def artefact_config(script)
      python_config_for(script)&.fetch(:artefact_config) || super
    end

    def config_schema_path(script)
      path = python_config_for(script)&.[](:config_schema_path)
      return path.call if path.respond_to?(:call)
      return path if path

      super
    end

    def scripts_for_logical_name(name)
      python_scripts = PYTHON_REGISTRY.select { |_id, config| config[:logical_name] == name.to_sym }.keys
      (super + python_scripts).uniq
    end

    def output_flag(script)
      python_config_for(script)&.fetch(:output_flag) || super
    end

    def requires_input?(script)
      python_config_for(script)&.fetch(:requires_input) || super
    end

    def requires_llm?(script)
      config = python_config_for(script)
      return config.fetch(:requires_llm, true) if config

      super
    end

    def model_flags(script)
      config = python_config_for(script)
      if config
        return [] unless config.fetch(:requires_llm, true)
        return config[:model_flags] if config.key?(:model_flags)

        return [{ role: :primary, flag: "--model_name" }]
      end

      super
    end

    def python_cli_for(script)
      python_config_for(script)&.fetch(:cli_name)
    end

    private

      def python_config_for(script)
        PYTHON_REGISTRY[script]
      end
  end
end
