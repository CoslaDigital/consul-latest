require "shellwords"

module Sensemaker
  class JobRunner
    TIMEOUT = 2800
    MAX_CLI_ERROR_OUTPUT = 20_000
    CLI_OUTPUT_TRUNCATION_OMISSION = "\n\n…[output truncated; showing end of log]…\n\n".freeze

    CONTEXT_SCRIPTS = %w[categorize report_text propositions refine_propositions].freeze
    INPUT_SCRIPTS = %w[categorize bridge_scores report_text propositions].freeze
    PKL_INPUT_SCRIPTS = %w[refine_propositions ranked_propositions].freeze
    LLM_SKIP_SCRIPTS = %w[report_ui ranked_propositions].freeze

    attr_reader :job

    def initialize(job)
      @job = job
    end

    def run
      execute_job_workflow
    end
    handle_asynchronously :run, queue: "sensemaker"

    def run_synchronously
      execute_job_workflow
    end

    def max_attempts
      1
    end

    def output_file_name
      job.output_file_name
    end

    def output_file
      "#{Sensemaker::Paths.sensemaker_data_folder}/#{output_file_name}"
    end

    def sensemaker_adapter
      runtime_config.adapter
    end

    def sensemaker_provider
      runtime_config.compat_provider
    end

    def sensemaker_api_key
      runtime_config.api_key
    end

    def sensemaker_base_url
      runtime_config.base_url
    end

    def self.enabled?
      Setting["feature.sensemaker"].present?
    end

    def build_command
      command_parts = [cli_executable.to_s]
      append_llm_flags(command_parts)
      append_script_flags(command_parts)
      append_additional_context_flags(command_parts)
      command_parts.join(" ")
    end

    private

      def llm_context
        @llm_context ||= Llm::Config.context
      end

      def runtime_config
        @runtime_config ||= Sensemaker::RuntimeConfig.new(setting: Setting, llm_context: llm_context)
      end

      def cli_executable
        cli_name = Sensemaker::Scripts.cli_for(job.script)
        return Sensemaker::Paths.node_cli(cli_name) if report_ui?

        Sensemaker::Paths.sensemaking_cli(cli_name)
      end

      def report_ui?
        job.script == "report_ui"
      end

      def ensure_work_dir!
        FileUtils.mkdir_p(job.work_dir)
      end

      def append_llm_flags(command_parts)
        return if llm_skip_script?

        model_name = runtime_config.model
        command_parts << "--model_name #{Shellwords.escape(model_name)}" if model_name.present?

        case sensemaker_adapter
        when "vertex"
          command_parts << "--adapter vertex"
          command_parts << "--vertex_project #{Shellwords.escape(runtime_config.vertex_project_id)}"
          command_parts << "--vertex_location #{Shellwords.escape(runtime_config.vertex_location)}"
        when "openai-compatible"
          command_parts << "--adapter openai-compatible"
          command_parts << "--provider #{Shellwords.escape(sensemaker_provider)}"
          command_parts << "--api_key #{Shellwords.escape(sensemaker_api_key)}" if sensemaker_api_key.present?
        when "gemini"
          command_parts << "--adapter gemini"
          command_parts << "--api_key #{Shellwords.escape(sensemaker_api_key)}" if sensemaker_api_key.present?
        end
        if sensemaker_base_url.present?
          command_parts << "--base_url #{Shellwords.escape(sensemaker_base_url)}"
        end
      end

      def append_script_flags(command_parts)
        work_dir = job.work_dir

        case job.script
        when "health_check"
          command_parts << "--output_file #{Shellwords.escape(File.join(work_dir, job.output_file_name))}"
        when "categorize"
          command_parts << "--input_file #{Shellwords.escape(job.input_file)}"
          command_parts << "--output_dir #{Shellwords.escape(work_dir)}"
          command_parts << "--skip_autoraters"
        when "bridge_scores"
          command_parts << "--input_csv #{Shellwords.escape(job.input_file)}"
          command_parts << "--output_csv #{Shellwords.escape(File.join(work_dir, job.output_file_name))}"
          command_parts << "--scorer_type GEMINI"
        when "report_text"
          command_parts << "--input_csv #{Shellwords.escape(job.input_file)}"
          command_parts << "--output_dir #{Shellwords.escape(work_dir)}"
        when "propositions"
          command_parts << "--r1_input_file #{Shellwords.escape(job.input_file)}"
          command_parts << "--output_dir #{Shellwords.escape(work_dir)}"
        when "refine_propositions"
          command_parts << "--input_pkl #{Shellwords.escape(job.input_file)}"
          command_parts << "--output_pkl #{Shellwords.escape(File.join(work_dir, job.output_file_name))}"
          command_parts << "--run_pav_selection"
          # TODO: consider passing different models
          # command_parts << "--simulated_jury_model_name #{Shellwords.escape(jury_model)}"
          # command_parts << "--nuanced_propositions_model_name #{Shellwords.escape(jury_model)}"
        when "ranked_propositions"
          output_path = File.join(work_dir, job.output_file_name)
          command_parts << "--query all_by_topic"
          command_parts << "--output_format csv"
          command_parts << Shellwords.escape(job.input_file)
          command_parts << "> #{Shellwords.escape(output_path)}"
        when "report_ui"
          command_parts << "inline"
          command_parts << "--opinions #{Shellwords.escape(report_ui_opinions_input_file.to_s)}"
          command_parts << "--summary #{Shellwords.escape(report_ui_summary_input_file.to_s)}"
          command_parts << "--output #{Shellwords.escape(work_dir)}"
        end
      end

      def append_additional_context_flags(command_parts)
        return unless CONTEXT_SCRIPTS.include?(job.script)

        context = job.additional_context.presence
        return if context.blank?

        command_parts << "--additional_context #{Shellwords.escape(context.to_s)}"
      end

      def execute_job_workflow
        job.update!(started_at: Time.current)

        comments_prepared_count = prepare_input_data
        return unless check_dependencies?
        return if execute_script.nil?
        return unless normalize_report_ui_output!

        attribs = { finished_at: Time.current }
        if job.has_outputs?
          attribs[:comments_analysed] = comments_prepared_count
        else
          attribs = attribs.merge(error: "Output file(s) not found")
        end
        job.update!(attribs)
      rescue Exception => e
        handle_error(e)
        raise e
      end

      def prepare_with_categorization_job
        categorization_job = Sensemaker::Job.create!(
          user: job.user,
          parent_job: job,
          analysable_type: job.analysable_type,
          analysable_id: job.analysable_id,
          script: "categorize",
          additional_context: job.additional_context
        )

        categorization_runner = Sensemaker::JobRunner.new(categorization_job)
        categorization_runner.run_synchronously

        if categorization_job.reload.errored?
          raise "Preparation job #{categorization_job.id} failed"
        end

        job.update!(input_file: categorization_job.categorize_output_csv)

        categorization_job.comments_analysed
      end

      def prepare_with_bridge_scores_job
        comments_count = prepare_with_categorization_job

        bridge_job = Sensemaker::Job.create!(
          user: job.user,
          parent_job: job,
          analysable_type: job.analysable_type,
          analysable_id: job.analysable_id,
          script: "bridge_scores",
          input_file: job.input_file,
          additional_context: job.additional_context
        )

        bridge_runner = Sensemaker::JobRunner.new(bridge_job)
        bridge_runner.run_synchronously

        if bridge_job.reload.errored?
          raise "Preparation job #{bridge_job.id} failed"
        end

        job.update!(input_file: bridge_job.bridge_scores_csv)

        bridge_job.comments_analysed || comments_count
      end

      def prepare_with_report_text_job
        comments_count = prepare_with_bridge_scores_job

        report_job = Sensemaker::Job.create!(
          user: job.user,
          parent_job: job,
          analysable_type: job.analysable_type,
          analysable_id: job.analysable_id,
          script: "report_text",
          input_file: job.input_file,
          additional_context: job.additional_context
        )

        report_runner = Sensemaker::JobRunner.new(report_job)
        report_runner.run_synchronously

        if report_job.reload.errored?
          raise "Preparation job #{report_job.id} failed"
        end

        job.update!(input_file: report_job.primary_artefact_path)

        report_job.comments_analysed || comments_count
      end

      def prepare_with_propositions_job
        comments_count = prepare_with_categorization_job

        propositions_job = Sensemaker::Job.create!(
          user: job.user,
          parent_job: job,
          analysable_type: job.analysable_type,
          analysable_id: job.analysable_id,
          script: "propositions",
          input_file: job.input_file,
          additional_context: job.additional_context
        )

        propositions_runner = Sensemaker::JobRunner.new(propositions_job)
        propositions_runner.run_synchronously

        if propositions_job.reload.errored?
          raise "Preparation job #{propositions_job.id} failed"
        end

        job.update!(input_file: propositions_job.world_model_pkl)

        propositions_job.comments_analysed || comments_count
      end

      def prepare_with_refine_propositions_job
        comments_count = prepare_with_propositions_job

        refine_job = Sensemaker::Job.create!(
          user: job.user,
          parent_job: job,
          analysable_type: job.analysable_type,
          analysable_id: job.analysable_id,
          script: "refine_propositions",
          input_file: job.input_file,
          additional_context: job.additional_context
        )

        refine_runner = Sensemaker::JobRunner.new(refine_job)
        refine_runner.run_synchronously

        if refine_job.reload.errored?
          raise "Preparation job #{refine_job.id} failed"
        end

        job.update!(input_file: refine_job.refined_world_model_pkl)

        refine_job.comments_analysed || comments_count
      end

      def prepare_input_data
        conversation = job.conversation
        comments_prepared_count = 0
        persisted_input_missing = job.read_attribute(:input_file).blank?

        if job.additional_context.blank?
          job.update!(additional_context: conversation.compile_context)
        end

        if persisted_input_missing
          case job.script
          when "categorize"
            comments_prepared_count = conversation.comments.size
            generated_input_path = job.default_input_csv
            ensure_work_dir!
            Sensemaker::CsvExporter.new(conversation).export_to_csv(generated_input_path)
            job.update!(input_file: generated_input_path)
          when "bridge_scores", "propositions"
            comments_prepared_count = prepare_with_categorization_job
          when "report_text"
            comments_prepared_count = prepare_with_bridge_scores_job
          when "refine_propositions"
            comments_prepared_count = prepare_with_propositions_job
          when "ranked_propositions"
            unless ranked_propositions_export_only?
              comments_prepared_count = prepare_with_refine_propositions_job
            end
          when "report_ui"
            comments_prepared_count = prepare_with_report_text_job
          end
        end

        comments_prepared_count
      end

      def check_dependencies?
        if Tenant.current_secrets.sensemaker_data_folder.blank?
          message = "Sensemaker data folder not configured. Add 'sensemaker_data_folder' to your secrets.yml"
          job.update!(finished_at: Time.current, error: message)
          Rails.logger.error(message)
          return false
        end

        return false unless file_exists?(Sensemaker::Paths.sensemaker_data_folder,
                                         description: "Sensemaker data folder")

        cli_path = cli_executable
        return false unless file_exists?(cli_path, description: "Sensemaker CLI (#{job.script})")

        if report_ui?
          return false unless file_exists?(
            report_ui_opinions_input_file,
            description: "Report UI opinions input"
          )
          return false unless file_exists?(
            report_ui_summary_input_file,
            description: "Report UI summary input"
          )

          return true
        end

        if ranked_propositions?
          return false unless file_exists?(job.input_file, description: "Refined world model input")

          return true
        end

        unless runtime_config.cli_supported?
          message = "Sensemaker LLM provider is not supported. Current provider: " \
                    "#{runtime_config.provider.presence || "(not set)"}."
          job.update!(finished_at: Time.current, error: message)
          Rails.logger.error(message)
          return false
        end

        if sensemaker_adapter == "vertex" && runtime_config.vertex_project_id.blank?
          message = "Vertex AI is not configured. Set tenant secrets llm.vertexai_project_id " \
                    "(and optionally vertexai_location)."
          job.update!(finished_at: Time.current, error: message)
          Rails.logger.error(message)
          return false
        end

        if runtime_config.model.blank?
          message = "Sensemaker requires an LLM model to be selected. Set it in Admin → Settings → LLM."
          job.update!(finished_at: Time.current, error: message)
          Rails.logger.error(message)
          return false
        end

        if sensemaker_adapter == "openai-compatible" && sensemaker_api_key.blank?
          message = "Sensemaker requires an API key for provider '#{sensemaker_provider}'. " \
                    "Set tenant secret llm.#{sensemaker_provider}_api_key."
          job.update!(finished_at: Time.current, error: message)
          Rails.logger.error(message)
          return false
        end

        if sensemaker_adapter == "gemini" && sensemaker_api_key.blank?
          message = "Sensemaker requires a Gemini API key. Set tenant secret llm.gemini_api_key."
          job.update!(finished_at: Time.current, error: message)
          Rails.logger.error(message)
          return false
        end

        key_path = Rails.application.secrets.google_application_credentials
        if key_path.present?
          path = (File.expand_path(key_path) == key_path) ? key_path : Rails.root.join(key_path).to_s
          return false unless file_exists?(path,
                                           description: "Key file (apis.google_application_credentials)")
        end

        if input_file_required? && !file_exists?(job.input_file, description: "Input file")
          return false
        end

        true
      end

      def report_ui_opinions_input_file
        bridge_job = job.children.where(script: "bridge_scores").order(:created_at).last
        bridge_job&.bridge_scores_csv
      end

      def report_ui_summary_input_file
        report_job = job.children.where(script: "report_text").order(:created_at).last
        report_job&.primary_artefact_path || job.input_file
      end

      def normalize_report_ui_output!
        return true unless report_ui?

        inline_index_path = File.join(job.work_dir, "inline", "index.html")
        report_html_path = File.join(job.work_dir, job.output_file_name)

        unless File.exist?(inline_index_path)
          message = "Report UI output not found: #{inline_index_path}"
          job.update!(finished_at: Time.current, error: message)
          Rails.logger.error(message)
          return false
        end

        FileUtils.cp(inline_index_path, report_html_path)
        true
      rescue => e
        message = "Failed to normalize report UI output: #{e.message}"
        job.update!(finished_at: Time.current, error: message)
        Rails.logger.error(message)
        false
      end

      def execute_script
        ensure_work_dir!
        command = build_command
        cmd = "cd #{job.work_dir} && timeout #{TIMEOUT} #{command}"
        Rails.logger.debug("Executing script: #{redact_command(cmd)}")
        output = `#{cmd} 2>&1`

        result = process_exit_status
        if result.eql?(0)
          Rails.logger.debug("Script executed successfully: #{output}")
          output
        else
          output = "Timeout: #{TIMEOUT} seconds\n#{output}" if result.eql?(124)
          truncated_output = truncate_cli_output(output)
          message = "Command: #{redact_command(cmd)}\n\n#{truncated_output}"
          job.update!(finished_at: Time.current, error: message)
          Rails.logger.error("Sensemaker::JobRunner error: #{truncated_output}")
          nil
        end
      end

      def handle_error(error)
        message = error.message
        backtrace = error.backtrace.select { |line| line.include?("job_runner.rb") }
        full_error = ([message] + backtrace).join("<br>")
        job.update!(finished_at: Time.current, error: full_error)
      end

      def process_exit_status
        $?.exitstatus
      end

      def file_exists?(file_path, description: "File or directory")
        return true if File.exist?(file_path)

        message = "#{description} not found: #{file_path}"
        job.update!(finished_at: Time.current, error: message)
        Rails.logger.error(message)
        false
      end

      def truncate_cli_output(output, max_length: MAX_CLI_ERROR_OUTPUT)
        text = output.to_s
        return text if text.length <= max_length

        omission = CLI_OUTPUT_TRUNCATION_OMISSION
        tail_length = max_length - omission.length
        omission + text[-tail_length..]
      end

      def redact_command(command)
        command.to_s
               .gsub(/--api_key\s+\S+/, "--api_key [REDACTED]")
               .gsub(/--apiKey\s+\S+/, "--apiKey [REDACTED]")
      end

      def llm_skip_script?
        LLM_SKIP_SCRIPTS.include?(job.script)
      end

      def ranked_propositions?
        job.script == "ranked_propositions"
      end

      def ranked_propositions_export_only?
        ranked_propositions? && job.read_attribute(:input_file).present?
      end

      def proposition_pipeline_script?
        Sensemaker::Scripts::PROPOSITION_PIPELINE_SCRIPTS.include?(job.script)
      end

      def input_file_required?
        INPUT_SCRIPTS.include?(job.script) || PKL_INPUT_SCRIPTS.include?(job.script)
      end
  end
end
