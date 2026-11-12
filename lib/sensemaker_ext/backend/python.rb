# frozen_string_literal: true

require "shellwords"
require "json"

module SensemakerExt
  module Backend
    class Python
      BOOLEAN_CLI_FLAGS = %w[skip_autoraters run_pav_selection].freeze

      attr_reader :job, :artefacts, :runtime_config

      def initialize(job, runtime_config:)
        @job = job
        @artefacts = job.artefacts
        @runtime_config = runtime_config
      end

      def cli_flags
        return report_ui_cli_flags if report_ui?

        flags = {}
        flags.merge!(llm_cli_flags)
        flags.merge!(script_cli_flags)
        if supports_additional_context?
          context = job.additional_context.to_s
          flags["additional_context"] = context unless context.empty?
        end
        flags
      end

      def persistable_cli_flags
        flags = cli_flags.dup
        flags["api_key"] = "[REDACTED]" if flags.key?("api_key")
        flags
      end

      def build_command
        return build_report_ui_command if report_ui?

        parts = [Shellwords.escape(cli_executable.to_s)]
        parts.concat(cli_flags.map { |key, value| format_cli_flag(key, value) })

        if job.script == "ranked_propositions"
          parts << Shellwords.escape(resolved_input_path)
          parts << "> #{Shellwords.escape(artefacts.default_output_path.to_s)}"
        end

        parts.join(" ")
      end

      def working_directory
        return Rails.root if report_ui?

        artefacts.job_directory
      end

      def check_runtime_dependencies?
        return check_report_ui_dependencies? if report_ui?

        unless system("which python3 > /dev/null 2>&1")
          job.record_error!("Python 3 not found in PATH")
          return false
        end

        return false unless file_exists?(Sensemaker::Paths.sensemaker_folder,
                                         description: "sensemaking-tools folder")
        return false unless file_exists?(Sensemaker::Paths.sensemaker_data_folder,
                                         description: "Sensemaker data folder")
        return false unless file_exists?(artefacts.job_directory,
                                         description: "Sensemaker job data folder")
        return false unless file_exists?(cli_executable, description: "Sensemaker Python CLI")
        return false if requires_input? && !file_exists?(resolved_input_path, description: "Input file")

        true
      end

      def after_input_prepared
        nil
      end

      def redact_command(command)
        command.to_s.gsub(/--api_key\s+\S+/, "--api_key [REDACTED]")
      end

      private

        def report_ui?
          job.script == "report_ui"
        end

        def build_report_ui_command
          prefix = "node #{Shellwords.escape(report_builder_cli.to_s)} inline"
          ([prefix] + cli_flags.map { |key, value| format_cli_flag(key, value) }).join(" ")
        end

        def report_ui_cli_flags
          {
            "bridging_scores" => bridging_scores_path.to_s,
            "summary" => summary_path.to_s,
            "output" => artefacts.default_output_path.to_s,
            "inputDir" => artefacts.job_directory.to_s,
            "config" => write_report_config
          }
        end

        def write_report_config
          config = job.run_options.to_h["config"]
          config = config.is_a?(Hash) ? config.deep_dup.stringify_keys : {}
          config.reject! { |_, value| value.blank? }
          config["title"] ||= job.conversation.target_label(format: :full)

          artefacts.write_report_config(config)
        end


        def report_builder_cli
          SensemakerExt::Paths.report_builder_folder.join("bin/cli.js")
        end

        def summary_path
          resolved_input_path
        end

        def bridging_scores_path
          artefacts.preparation_output_for("bridge_scores")
        end

        def check_report_ui_dependencies?
          unless system("which node > /dev/null 2>&1")
            job.record_error!("Node.js not found in PATH")
            return false
          end

          return false unless file_exists?(Sensemaker::Paths.sensemaker_data_folder,
                                           description: "Sensemaker data folder")
          return false unless file_exists?(artefacts.job_directory,
                                           description: "Sensemaker job data folder")
          return false unless file_exists?(SensemakerExt::Paths.report_builder_folder,
                                           description: "sensemaking-report-builder package folder")
          return false unless file_exists?(report_builder_cli,
                                           description: "sensemaking-report-builder CLI")
          return false unless file_exists?(summary_path, description: "Report summary JSON")
          return false unless file_exists?(bridging_scores_path, description: "Bridging scores CSV")

          true
        end

        def cli_executable
          cli_name = Sensemaker::ScriptRegistry.python_cli_for(job.script)
          raise ArgumentError, "No Python CLI mapped for #{job.script}" if cli_name.blank?

          Sensemaker::Paths.sensemaker_folder.join("venv/bin/#{cli_name}")
        end

        def llm_cli_flags
          return {} unless Sensemaker::ScriptRegistry.requires_llm?(job.script)

          flags = {}
          Sensemaker::ScriptRegistry.model_flags(job.script).each do |entry|
            model_name = runtime_config.model_for(entry[:role])
            next if model_name.blank?

            flags[entry[:flag].to_s.delete_prefix("--")] = model_name
          end

          case runtime_config.adapter
          when "vertex"
            flags["adapter"] = "vertex"
            flags["vertex_project"] = runtime_config.vertex_project_id
            flags["vertex_location"] = runtime_config.vertex_location
          when "gemini"
            flags["adapter"] = "gemini"
            api_key = runtime_config.api_key
            flags["api_key"] = api_key if api_key.present?
          when "openai-compatible"
            flags["adapter"] = "openai-compatible"
            flags["provider"] = runtime_config.compat_provider
            api_key = runtime_config.api_key
            flags["api_key"] = api_key if api_key.present?
          end

          base_url = runtime_config.base_url
          flags["base_url"] = base_url if base_url.present?
          flags
        end

        def script_cli_flags
          input_path = resolved_input_path
          output_path = artefacts.default_output_path.to_s
          output_dir = artefacts.job_directory.to_s

          case job.script
          when "health_check"
            { "output_file" => output_path }
          when "categorize"
            {
              "input_file" => input_path,
              "output_dir" => output_dir,
              "skip_autoraters" => true
            }
          when "bridge_scores"
            {
              "input_csv" => input_path,
              "output_csv" => output_path,
              "scorer_type" => "GEMINI"
            }
          when "report_text"
            {
              "input_csv" => input_path,
              "output_dir" => output_dir
            }
          when "propositions"
            {
              "r1_input_file" => input_path,
              "output_dir" => output_dir
            }
          when "refine_propositions"
            {
              "input_pkl" => input_path,
              "output_pkl" => output_path,
              "run_pav_selection" => true
            }
          when "ranked_propositions"
            {
              "query" => "all_by_topic",
              "output_format" => "csv"
            }
          else
            raise ArgumentError, "Unsupported python script for spike: #{job.script}"
          end
        end

        def format_cli_flag(key, value)
          return "--#{key}" if BOOLEAN_CLI_FLAGS.include?(key) && value == true

          "--#{key} #{Shellwords.escape(value.to_s)}"
        end

        def supports_additional_context?
          %w[categorize report_text propositions refine_propositions].include?(job.script)
        end

        def requires_input?
          Sensemaker::ScriptRegistry.requires_input?(job.script)
        end

        def resolved_input_path
          path = artefacts.input_path.to_s
          case job.script
          when "bridge_scores", "propositions"
            return path if path.end_with?("_without_other_filtered.csv")

            "#{path}_without_other_filtered.csv"
          when "report_ui"
            return path if path.end_with?(".json")

            "#{path}.json"
          else
            path
          end
        end

        def file_exists?(file_path, description:)
          return true if file_path.present? && File.exist?(file_path)

          job.record_error!("#{description} not found: #{file_path}")
          false
        end
    end
  end
end
