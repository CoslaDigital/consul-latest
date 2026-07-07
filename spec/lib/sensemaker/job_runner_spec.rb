require "rails_helper"

describe Sensemaker::JobRunner do
  let(:user) { create(:user) }
  let(:debate) { create(:debate) }
  let(:job) do
    create(:sensemaker_job,
           analysable_type: "Debate",
           analysable_id: debate.id,
           script: "categorize",
           user: user,
           started_at: Time.current,
           additional_context: "Debate context for categorization")
  end
  let(:cli_path) { "/tmp/sensemaking-categorize" }
  let(:node_cli_path) { "/tmp/sensemaking-report" }

  shared_context "sensemaker paths stubbed" do
    let(:data_folder) { "/tmp/sensemaker_test_folder/data" }

    before do
      allow(Sensemaker::Paths).to receive_messages(sensemaker_data_folder: data_folder,
                                                   sensemaking_cli: cli_path,
                                                   node_cli: node_cli_path)
    end
  end

  describe "#initialize" do
    it "initializes with the provided job" do
      service = Sensemaker::JobRunner.new(job)
      expect(service.job).to eq(job)
    end
  end

  describe "#run" do
    let(:service) { Sensemaker::JobRunner.new(job) }

    before do
      allow(File).to receive(:exist?).and_return(true)
      allow(service).to receive(:check_dependencies?).and_return(true)
    end

    it "runs the complete workflow successfully" do
      allow(service).to receive(:execute_script).and_return("ok")

      service.run

      job.reload
      expect(job.started_at).to be_present
      expect(job.finished_at).to be_present
    end

    it "stops if check_dependencies? returns false" do
      allow(service).to receive(:check_dependencies?).and_return(false)
      expect(service).not_to receive(:execute_script)

      service.run
    end

    it "stops if execute_script returns nil" do
      expect(service).to receive(:execute_script).and_return(nil)

      service.run
    end

    it "handles errors and updates the job" do
      expect(service).to receive(:execute_script).and_raise(StandardError.new("Test error"))

      expect { service.run }.to raise_error(StandardError)

      job.reload
      expect(job.finished_at).to be_present
      expect(job.error).to include("Test error")
    end
  end

  describe "#check_dependencies?" do
    let(:service) { Sensemaker::JobRunner.new(job) }
    let(:llm_config) do
      double(
        "LLM config",
        vertexai_project_id: "sensemaker-466109",
        vertexai_location: "global",
        openai_api_key: "openai-secret",
        openai_api_base: "https://openai-proxy.example.com/v1",
        mistral_api_key: "mistral-secret"
      )
    end
    let(:llm_context) { double("LLM context", config: llm_config) }

    include_context "sensemaker paths stubbed"

    before do
      allow(File).to receive(:exist?).and_return(true)
      allow(Llm::Config).to receive(:context).and_return(llm_context)
      allow(Setting).to receive(:[]).and_call_original
      allow(Setting).to receive(:[]).with("llm.provider").and_return("VertexAI")
      allow(Setting).to receive(:[]).with("llm.model").and_return("gemini-2.5-flash-lite")
    end

    it "returns true when all dependencies are available" do
      result = service.send(:check_dependencies?)
      expect(result).to be true
    end

    it "returns true for report_ui when node CLI and prepared inputs exist" do
      job.script = "report_ui"
      bridge_job = create(:sensemaker_job, :bridge_scores, parent_job: job, user: user)
      report_job = create(:sensemaker_job, :report_text, parent_job: job, user: user)
      allow(bridge_job).to receive(:bridge_scores_csv).and_return("/tmp/bridging_scores.csv")
      allow(report_job).to receive(:primary_artefact_path).and_return("/tmp/report_data.json")
      allow(File).to receive(:exist?).with("/tmp/bridging_scores.csv").and_return(true)
      allow(File).to receive(:exist?).with("/tmp/report_data.json").and_return(true)
      allow(Sensemaker::Paths).to receive(:node_cli).with("sensemaking-report").and_return(node_cli_path)

      result = service.send(:check_dependencies?)
      expect(result).to be true
    end

    {
      "sensemaker_data_folder is not configured" => [
        -> { allow(Tenant.current_secrets).to receive(:sensemaker_data_folder).and_return(nil) },
        "Sensemaker data folder not configured"
      ],
      "Vertex AI project_id is not configured" => [
        -> { allow(llm_config).to receive(:vertexai_project_id).and_return(nil) },
        "Vertex AI is not configured"
      ],
      "LLM provider is unsupported" => [
        -> { allow(Setting).to receive(:[]).with("llm.provider").and_return("ollama") },
        "Sensemaker LLM provider is not supported"
      ],
      "LLM model is not selected" => [
        -> { allow(Setting).to receive(:[]).with("llm.model").and_return(nil) },
        "Sensemaker requires an LLM model to be selected"
      ],
      "the sensemaking data folder does not exist" => [
        -> {
          allow(File).to receive(:exist?).with(Sensemaker::Paths.sensemaker_data_folder).and_return(false)
        },
        "Sensemaker data folder not found"
      ],
      "the input file does not exist" => [
        -> {
          allow(File).to receive(:exist?).with(Sensemaker::Paths.sensemaker_data_folder).and_return(true)
          allow(File).to receive(:exist?).with(cli_path).and_return(true)
          allow(File).to receive(:exist?).with(job.input_file).and_return(false)
        },
        "Input file not found"
      ],
      "apis.google_application_credentials is set but key file does not exist" => [
        -> {
          allow(Rails.application.secrets).to receive(:google_application_credentials)
          .and_return("/nonexistent/key.json")
          allow(File).to receive(:exist?).with("/nonexistent/key.json").and_return(false)
          allow(File).to receive(:exist?).with(Sensemaker::Paths.sensemaker_data_folder).and_return(true)
          allow(File).to receive(:exist?).with(cli_path).and_return(true)
          allow(File).to receive(:exist?).with(job.input_file).and_return(true)
        },
        "Key file (apis.google_application_credentials) not found"
      ],
      "the CLI executable does not exist" => [
        -> {
          allow(File).to receive(:exist?).with(Sensemaker::Paths.sensemaker_data_folder).and_return(true)
          allow(File).to receive(:exist?).with(cli_path).and_return(false)
        },
        "Sensemaker CLI (categorize) not found"
      ]
    }.each do |description, (setup, error_substring)|
      it "returns false when #{description}" do
        instance_exec(&setup)
        result = service.send(:check_dependencies?)
        expect(result).to be false
        job.reload
        expect(job.finished_at).to be_present
        expect(job.error).to include(error_substring)
      end
    end

    it "returns true for OpenAI-compatible provider with API key" do
      allow(Setting).to receive(:[]).with("llm.provider").and_return("OpenAI")
      allow(llm_config).to receive(:openai_api_key).and_return("tenant-openai-key")

      result = service.send(:check_dependencies?)
      expect(result).to be true
    end

    it "returns false for OpenAI-compatible provider without API key" do
      allow(Setting).to receive(:[]).with("llm.provider").and_return("OpenAI")
      allow(llm_config).to receive(:openai_api_key).and_return(nil)

      result = service.send(:check_dependencies?)
      expect(result).to be false
      job.reload
      expect(job.error).to include("Sensemaker requires an API key for provider 'openai'")
    end

    it "returns true for Gemini provider with API key" do
      allow(Setting).to receive(:[]).with("llm.provider").and_return("Gemini")
      allow(llm_config).to receive(:gemini_api_key).and_return("tenant-gemini-key")

      result = service.send(:check_dependencies?)
      expect(result).to be true
    end

    it "returns false for Gemini provider without API key" do
      allow(Setting).to receive(:[]).with("llm.provider").and_return("Gemini")
      allow(llm_config).to receive(:gemini_api_key).and_return(nil)

      result = service.send(:check_dependencies?)
      expect(result).to be false
      job.reload
      expect(job.error).to include("Sensemaker requires a Gemini API key")
    end

    it "returns false for report_ui when node CLI is missing" do
      job.script = "report_ui"
      allow(Sensemaker::Paths).to receive(:node_cli)
        .with("sensemaking-report").and_raise("Sensemaker Node CLI not found or not executable")

      expect { service.send(:check_dependencies?) }.to raise_error(/Sensemaker Node CLI not found/)
    end

    it "returns false for report_ui when prepared inputs are missing" do
      job.script = "report_ui"
      bridge_job = create(:sensemaker_job, :bridge_scores, parent_job: job, user: user)
      report_job = create(:sensemaker_job, :report_text, parent_job: job, user: user)
      allow(Sensemaker::Paths).to receive(:node_cli).with("sensemaking-report").and_return(node_cli_path)
      allow(File).to receive(:exist?).with(bridge_job.bridge_scores_csv).and_return(false)
      allow(File).to receive(:exist?).with(report_job.primary_artefact_path).and_return(true)

      result = service.send(:check_dependencies?)

      expect(result).to be false
      job.reload
      expect(job.error).to include("Report UI opinions input not found")
    end

    context "when script is health_check" do
      let(:job) { create(:sensemaker_job, :health_check, user: user) }

      it "does not require an input file" do
        allow(File).to receive(:exist?).with(job.input_file).and_return(false)

        result = service.send(:check_dependencies?)
        expect(result).to be true
      end
    end
  end

  describe "#execute_script" do
    let(:service) { Sensemaker::JobRunner.new(job) }

    include_context "sensemaker paths stubbed"

    before do
      allow(File).to receive(:exist?).and_return(true)
      allow(Setting).to receive(:[]).and_call_original
      allow(Setting).to receive(:[]).with("llm.provider").and_return("VertexAI")
      allow(Setting).to receive(:[]).with("llm.model").and_return("gemini-2.5-flash-lite")
      allow(FileUtils).to receive(:mkdir_p)
    end

    it "returns stdout when the script executes successfully" do
      timeout = Sensemaker::JobRunner::TIMEOUT
      expected_command = %r{cd .*job-#{job.id}.* && timeout #{timeout} .*sensemaking-categorize}
      expect(service).to receive(:`).with(expected_command).and_return("Success output")

      allow(service).to receive(:process_exit_status).and_return(0)

      result = service.send(:execute_script)

      expect(result).to eq("Success output")
    end

    it "returns empty string when ranked_propositions redirects stdout to a file" do
      job.update!(script: "ranked_propositions")
      job[:input_file] = "/tmp/refined_world_model.pkl"
      allow(Sensemaker::Paths).to receive(:sensemaking_cli)
        .with("sensemaking-world-model").and_return("/tmp/sensemaking-world-model")

      timeout = Sensemaker::JobRunner::TIMEOUT
      expect(service).to receive(:`).with(%r{cd .*job-#{job.id}.* && timeout #{timeout} }).and_return("")
      allow(service).to receive(:process_exit_status).and_return(0)

      result = service.send(:execute_script)

      expect(result).to eq("")
    end

    it "returns nil and updates the job when the script fails" do
      timeout = Sensemaker::JobRunner::TIMEOUT
      expected_command = %r{cd .* && timeout #{timeout} .*}
      expect(service).to receive(:`).with(expected_command).and_return("Error output")

      allow(service).to receive(:process_exit_status).and_return(1)

      result = service.send(:execute_script)

      expect(result).to be nil

      job.reload
      expect(job.finished_at).to be_present
      expect(job.error).to include("Command:")
      expect(job.error).to include("Error output")
    end

    it "keeps the end of long CLI output in job.error" do
      suffix = "FINAL_ERROR: something broke at the end"
      long_output = ("x" * (Sensemaker::JobRunner::MAX_CLI_ERROR_OUTPUT + 1)) + suffix
      timeout = Sensemaker::JobRunner::TIMEOUT
      expect(service).to receive(:`).with(%r{cd .* && timeout #{timeout} }).and_return(long_output)
      allow(service).to receive(:process_exit_status).and_return(1)

      service.send(:execute_script)
      job.reload

      expect(job.error).to include("FINAL_ERROR: something broke at the end")
      expect(job.error).to include("[output truncated; showing end of log]")
      expect(job.error.length).to be <= Sensemaker::JobRunner::MAX_CLI_ERROR_OUTPUT + 500
    end

    it "redacts api keys in stored command errors" do
      allow(Setting).to receive(:[]).with("llm.provider").and_return("OpenAI")
      allow(service).to receive_messages(
        sensemaker_adapter: "openai-compatible",
        sensemaker_provider: "openai",
        sensemaker_api_key: "super-secret-key",
        process_exit_status: 1
      )
      expect(service).to receive(:`).with(%r{--api_key super-secret-key}).and_return("Error output")

      service.send(:execute_script)
      job.reload
      expect(job.error).to include("--api_key [REDACTED]")
      expect(job.error).not_to include("super-secret-key")
    end
  end

  describe "#truncate_cli_output" do
    let(:service) { Sensemaker::JobRunner.new(job) }

    it "returns short output unchanged" do
      expect(service.send(:truncate_cli_output, "short error")).to eq("short error")
    end

    it "keeps the tail of long output" do
      suffix = "Traceback: real failure"
      long = ("x" * 250) + suffix
      result = service.send(:truncate_cli_output, long, max_length: 200)

      expect(result).to end_with(suffix)
      expect(result).to include("[output truncated; showing end of log]")
    end
  end

  describe "#build_command" do
    let(:service) { Sensemaker::JobRunner.new(job) }
    let(:llm_config) do
      double(
        "LLM config",
        vertexai_project_id: "sensemaker-466109",
        vertexai_location: "global",
        openai_api_key: "openai-secret",
        openai_api_base: "https://openai-proxy.example.com/v1",
        mistral_api_key: "mistral-secret"
      )
    end
    let(:llm_context) { double("LLM context", config: llm_config) }

    include_context "sensemaker paths stubbed"

    before do
      allow(Llm::Config).to receive(:context).and_return(llm_context)
      allow(Setting).to receive(:[]).and_call_original
      allow(Setting).to receive(:[]).with("llm.provider").and_return("VertexAI")
      allow(Setting).to receive(:[]).with("llm.model").and_return("gemini-2.5-flash-lite")
      job[:input_file] = "#{data_folder}/job-#{job.id}/input.csv"
    end

    shared_examples "python runner command" do |script_name, cli_name|
      it "builds the #{script_name} command with Python flags" do
        allow(Sensemaker::Paths).to receive(:sensemaking_cli).with(cli_name).and_return("/tmp/#{cli_name}")
        job.script = script_name

        command = service.build_command

        expect(command).to include("/tmp/#{cli_name}")
        expect(command).to include("--adapter vertex")
        expect(command).to include("--vertex_project sensemaker-466109")
        expect(command).to include("--vertex_location global")
        expect(command).to include("--model_name gemini-2.5-flash-lite")
      end
    end

    it_behaves_like "python runner command", "categorize", "sensemaking-categorize"
    it_behaves_like "python runner command", "bridge_scores", "sensemaking-bridge-scores"
    it_behaves_like "python runner command", "report_text", "sensemaking-report-text"
    it_behaves_like "python runner command", "health_check", "sensemaking-health-check"

    it "includes categorize input and output paths" do
      command = service.build_command

      expect(command).to include("--input_file")
      expect(command).to include("--output_dir")
      expect(command).to include("--skip_autoraters")
      expect(command).to include(job.input_file)
      expect(command).to include("#{data_folder}/job-#{job.id}")
    end

    it "does not pass skip_autoraters for bridge_scores" do
      job.script = "bridge_scores"
      allow(Sensemaker::Paths).to receive(:sensemaking_cli)
        .with("sensemaking-bridge-scores").and_return("/tmp/sensemaking-bridge-scores")

      expect(service.build_command).not_to include("--skip_autoraters")
    end

    it "includes inline additional_context for categorize" do
      command = service.build_command

      expect(command).to include("--additional_context")
      expect(command).to include(Shellwords.escape("Debate context for categorization"))
    end

    it "omits additional_context for health_check" do
      job.script = "health_check"
      allow(Sensemaker::Paths).to receive(:sensemaking_cli)
        .with("sensemaking-health-check").and_return("/tmp/sensemaking-health-check")

      command = service.build_command

      expect(command).not_to include("--additional_context")
      expect(command).to include("--output_file")
    end

    it "returns the correct command for OpenAI-compatible providers" do
      allow(Setting).to receive(:[]).with("llm.provider").and_return("OpenAI")

      command = service.build_command
      expect(command).to include("--adapter openai-compatible")
      expect(command).to include("--provider openai")
      expect(command).to include("--api_key openai-secret")
      expect(command).to include("--base_url https://openai-proxy.example.com/v1")
      expect(command).not_to include("--vertex_project")
    end

    it "returns the correct command for Gemini provider" do
      allow(Setting).to receive(:[]).with("llm.provider").and_return("Gemini")
      allow(llm_config).to receive(:gemini_api_key).and_return("gemini-secret")

      command = service.build_command
      expect(command).to include("--adapter gemini")
      expect(command).to include("--api_key gemini-secret")
      expect(command).not_to include("--vertex_project")
      expect(command).not_to include("--provider")
    end

    it "includes bridge_scores flags" do
      job.script = "bridge_scores"
      allow(Sensemaker::Paths).to receive(:sensemaking_cli)
        .with("sensemaking-bridge-scores").and_return("/tmp/sensemaking-bridge-scores")

      command = service.build_command

      expect(command).to include("--input_csv")
      expect(command).to include("--output_csv")
      expect(command).to include("--scorer_type GEMINI")
      expect(command).not_to include("--additional_context")
    end

    it "builds report_ui command with inline report arguments" do
      job.script = "report_ui"
      bridge_job = create(:sensemaker_job, :bridge_scores, parent_job: job, user: user)
      report_job = create(:sensemaker_job, :report_text, parent_job: job, user: user)
      allow(Sensemaker::Paths).to receive(:node_cli).with("sensemaking-report").and_return(node_cli_path)

      command = service.build_command

      expect(command).to include(node_cli_path)
      expect(command).to include("inline")
      expect(command).to include("--opinions #{bridge_job.bridge_scores_csv}")
      expect(command).to include("--summary #{report_job.primary_artefact_path}")
      expect(command).to include("--output #{data_folder}/job-#{job.id}")
      expect(command).not_to include("--adapter")
      expect(command).not_to include("--model_name")
    end

    it "builds ranked_propositions command with redirect and no LLM flags" do
      job.script = "ranked_propositions"
      pkl_path = "/tmp/refined_world_model.pkl"
      job[:input_file] = pkl_path
      allow(Sensemaker::Paths).to receive(:sensemaking_cli)
        .with("sensemaking-world-model").and_return("/tmp/sensemaking-world-model")

      command = service.build_command

      expect(command).to include("/tmp/sensemaking-world-model")
      expect(command).to include("--query all_by_topic")
      expect(command).to include("--output_format csv")
      expect(command).to include(Shellwords.escape(pkl_path))
      csv_output = "#{data_folder}/job-#{job.id}/final_propositions_by_topic.csv"
      expect(command).to include("> #{Shellwords.escape(csv_output)}")
      expect(command).not_to include("--adapter")
      expect(command).not_to include("--model_name")
    end

    it_behaves_like "python runner command", "propositions", "sensemaking-propositions"

    it "includes propositions flags" do
      job.script = "propositions"
      job[:input_file] = "/tmp/categorized.csv"
      allow(Sensemaker::Paths).to receive(:sensemaking_cli)
        .with("sensemaking-propositions").and_return("/tmp/sensemaking-propositions")

      command = service.build_command

      expect(command).to include("--r1_input_file")
      expect(command).to include("--output_dir")
      expect(command).to include(Shellwords.escape("/tmp/categorized.csv"))
    end

    it "includes refine_propositions flags with model_name only" do
      job.script = "refine_propositions"
      job[:input_file] = "/tmp/world_model.pkl"
      allow(Sensemaker::Paths).to receive(:sensemaking_cli)
        .with("sensemaking-refine-propositions").and_return("/tmp/sensemaking-refine-propositions")

      command = service.build_command

      expect(command).to include("--adapter vertex")
      expect(command).to include("--model_name gemini-2.5-flash-lite")
      expect(command).to include("--input_pkl")
      expect(command).to include("--output_pkl")
      expect(command).to include("--run_pav_selection")
    end
  end

  describe "#execute_job_workflow" do
    let(:service) { Sensemaker::JobRunner.new(job) }
    include_context "sensemaker paths stubbed"

    before do
      allow(File).to receive(:exist?).and_return(true)
      allow(service).to receive_messages(check_dependencies?: true, execute_script: "success")
      allow(service).to receive(:prepare_input_data)
    end

    context "when all output files exist" do
      it "sets finished_at and does not set error" do
        allow(job).to receive(:has_outputs?).and_return(true)

        service.send(:execute_job_workflow)

        job.reload
        expect(job.finished_at).to be_present
        expect(job.error).to be(nil)
      end

      it "sets comments_analysed count when job finishes successfully" do
        allow(job).to receive(:has_outputs?).and_return(true)
        allow(service).to receive(:prepare_input_data).and_return(5)

        service.send(:execute_job_workflow)

        job.reload
        expect(job.comments_analysed).to eq(5)
      end

      it "triggers the callback to set persisted_output (relative path for deploy safety)" do
        output_path = "#{data_folder}/job-#{job.id}/categorized_without_other_filtered.csv"
        allow(File).to receive(:exist?).with(output_path).and_return(true)
        allow(job).to receive(:has_outputs?).and_return(true)

        service.send(:execute_job_workflow)

        job.reload
        expect(job.persisted_output).to eq(job.relative_output_path)
      end
    end

    context "when output files do not exist" do
      it "sets finished_at and error message" do
        allow(job).to receive(:has_outputs?).and_return(false)

        service.send(:execute_job_workflow)

        job.reload
        expect(job.finished_at).to be_present
        expect(job.error).to eq("Output file(s) not found")
      end
    end

    context "when script is report_ui" do
      before do
        job.update!(script: "report_ui")
      end

      it "normalizes inline output before marking job successful" do
        allow(job).to receive(:has_outputs?).and_return(true)
        expect(service).to receive(:normalize_report_ui_output!).and_return(true)

        service.send(:execute_job_workflow)

        job.reload
        expect(job.finished_at).to be_present
        expect(job.error).to be(nil)
      end
    end

    context "when script is ranked_propositions and CLI stdout is empty (shell redirect)" do
      before do
        job.update!(script: "ranked_propositions")
        allow(service).to receive(:execute_script).and_return("")
      end

      it "sets finished_at when output file exists" do
        allow(job).to receive(:has_outputs?).and_return(true)

        service.send(:execute_job_workflow)

        job.reload
        expect(job.finished_at).to be_present
        expect(job.error).to be(nil)
      end
    end
  end

  describe "#prepare_input_data" do
    let(:service) { Sensemaker::JobRunner.new(job) }
    let(:mock_exporter) { instance_double(Sensemaker::CsvExporter) }
    let(:input_file_path) { "#{Sensemaker::Paths.sensemaker_data_folder}/job-#{job.id}/input.csv" }
    let(:mock_conversation) { instance_double(Sensemaker::Conversation) }
    let(:mock_comments) { Array.new(7) { double("comment") } }

    include_context "sensemaker paths stubbed"

    before do
      allow(Sensemaker::CsvExporter).to receive(:new).and_return(mock_exporter)
      allow(mock_exporter).to receive(:export_to_csv)
      allow(job).to receive(:conversation).and_return(mock_conversation)
      allow(mock_conversation).to receive_messages(
        comments: mock_comments,
        compile_context: "Test context"
      )
      allow(FileUtils).to receive(:mkdir_p)
    end

    it "creates a CsvExporter with the job's conversation" do
      service.send(:prepare_input_data)

      expect(Sensemaker::CsvExporter).to have_received(:new).with(mock_conversation)
    end

    it "exports CSV data to default_input_csv" do
      service.send(:prepare_input_data)

      expect(mock_exporter).to have_received(:export_to_csv).with(input_file_path)
    end

    it "persists input_file after exporting CSV when input_file is blank" do
      expect(job.read_attribute(:input_file)).to be(nil)

      service.send(:prepare_input_data)

      expect(job.reload.read_attribute(:input_file)).to eq(input_file_path)
    end

    it "updates the job with additional context when blank" do
      job.update!(additional_context: "")
      allow(job).to receive(:conversation).and_call_original

      service.send(:prepare_input_data)

      job.reload
      expect(job.additional_context).to be_present
      expect(job.additional_context).to include("Analysing Citizen debate")
      expect(job.additional_context).to include(debate.title)
    end

    it "returns the count of comments from conversation when input_file is blank" do
      result = service.send(:prepare_input_data)

      expect(result).to eq(7)
    end

    context "when script is bridge_scores with blank input_file" do
      let(:job) { create(:sensemaker_job, :bridge_scores, user: user, additional_context: "ctx") }
      let(:categorization_job) { create(:sensemaker_job, :categorize, user: user, comments_analysed: 10) }

      before do
        allow(service).to receive(:prepare_with_categorization_job).and_return(10)
        allow(categorization_job).to receive(:categorize_output_csv).and_return("/tmp/categorized.csv")
      end

      it "calls prepare_with_categorization_job" do
        service.send(:prepare_input_data)

        expect(service).to have_received(:prepare_with_categorization_job)
      end
    end

    context "when script is report_text with blank input_file" do
      let(:job) { create(:sensemaker_job, :report_text, user: user) }

      it "calls prepare_with_bridge_scores_job" do
        allow(service).to receive(:prepare_with_bridge_scores_job).and_return(8)

        result = service.send(:prepare_input_data)

        expect(service).to have_received(:prepare_with_bridge_scores_job)
        expect(result).to eq(8)
      end
    end

    context "when input_file is already set" do
      before do
        job[:input_file] = "/existing/input.csv"
      end

      it "returns 0 and does not export CSV" do
        result = service.send(:prepare_input_data)

        expect(result).to eq(0)
        expect(mock_exporter).not_to have_received(:export_to_csv)
      end
    end

    context "when script is propositions with blank input_file" do
      let(:job) { create(:sensemaker_job, :propositions, user: user) }

      it "calls prepare_with_categorization_job" do
        allow(service).to receive(:prepare_with_categorization_job).and_return(9)

        result = service.send(:prepare_input_data)

        expect(service).to have_received(:prepare_with_categorization_job)
        expect(result).to eq(9)
      end
    end

    context "when script is refine_propositions with blank input_file" do
      let(:job) { create(:sensemaker_job, :refine_propositions, user: user) }

      it "calls prepare_with_propositions_job" do
        allow(service).to receive(:prepare_with_propositions_job).and_return(11)

        result = service.send(:prepare_input_data)

        expect(service).to have_received(:prepare_with_propositions_job)
        expect(result).to eq(11)
      end
    end

    context "when script is ranked_propositions with blank input_file" do
      let(:job) { create(:sensemaker_job, :ranked_propositions, user: user) }

      it "calls prepare_with_refine_propositions_job" do
        allow(service).to receive(:prepare_with_refine_propositions_job).and_return(12)

        result = service.send(:prepare_input_data)

        expect(service).to have_received(:prepare_with_refine_propositions_job)
        expect(result).to eq(12)
      end
    end

    context "when script is ranked_propositions with input_file preset" do
      let(:job) do
        create(:sensemaker_job, :ranked_propositions, user: user, input_file: "/tmp/refined.pkl")
      end

      it "skips preparation chain" do
        expect(service).not_to receive(:prepare_with_refine_propositions_job)

        result = service.send(:prepare_input_data)

        expect(result).to eq(0)
      end
    end
  end
end
