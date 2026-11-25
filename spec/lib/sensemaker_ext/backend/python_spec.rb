# frozen_string_literal: true

require "rails_helper"

describe SensemakerExt::Backend::Python do
  include_context "sensemaker llm config"

  let(:user) { create(:user) }
  let(:debate) { create(:debate) }
  let(:data_folder) { "/tmp/sensemaker_test_folder/data" }
  let(:report_builder_folder) { Rails.root.join("tmp/sensemaker_test_folder/report-builder") }
  let(:runtime_config) do
    Sensemaker::RuntimeConfig.new(setting: Setting, llm_context: Llm::Config.context)
  end

  before do
    SensemakerExt::Loader.install!
    allow(Sensemaker::Paths).to receive(:sensemaker_data_folder).and_return(data_folder)
    allow(Sensemaker::Paths).to receive(:job_directory) do |j|
      "#{data_folder}/job-#{j.id}"
    end
    allow(SensemakerExt::Paths).to receive(:report_builder_folder).and_return(report_builder_folder)
    FileUtils.mkdir_p(report_builder_folder.join("bin"))
    File.write(report_builder_folder.join("bin/cli.js"), "#!/usr/bin/env node\n")
  end

  describe "report_ui" do
    let(:summary_path) { "#{data_folder}/job-summary/report_data.json" }
    let(:bridging_path) { "#{data_folder}/job-bridge/bridging_scores.csv" }

    let(:job) do
      create(:sensemaker_job,
             analysable_type: "Debate",
             analysable_id: debate.id,
             script: "report_ui",
             user: user,
             started_at: Time.current,
             input_file: summary_path,
             additional_context: "")
    end
    let(:backend) { SensemakerExt::Backend::Python.new(job, runtime_config: runtime_config) }

    let!(:report_text_job) do
      create(:sensemaker_job,
             parent_job: job,
             analysable_type: "Debate",
             analysable_id: debate.id,
             script: "report_text",
             user: user,
             started_at: Time.current)
    end
    let!(:bridge_job) do
      create(:sensemaker_job,
             parent_job: report_text_job,
             analysable_type: "Debate",
             analysable_id: debate.id,
             script: "bridge_scores",
             user: user,
             started_at: Time.current)
    end

    before do
      FileUtils.mkdir_p(File.dirname(summary_path))
      FileUtils.mkdir_p(File.dirname(bridging_path))
      FileUtils.mkdir_p(Sensemaker::Paths.job_directory(job))
      FileUtils.mkdir_p(Sensemaker::Paths.job_directory(bridge_job))
      File.write(summary_path, '{"text":"hi","sub_contents":[]}')
      File.write(bridging_path, "topic,opinion,quote,participant_id\n")
      # Place bridging output where JobArtefacts expects it for bridge_scores
      FileUtils.cp(
        bridging_path,
        File.join(Sensemaker::Paths.job_directory(bridge_job), "bridging_scores.csv")
      )
    end

    describe "#build_command" do
      it "invokes the report-builder CLI with summary, bridging scores, and output file" do
        conversation = instance_double(Sensemaker::Conversation)
        allow(job).to receive(:conversation).and_return(conversation)
        allow(conversation).to receive(:target_label).with(format: :full).and_return("Test Label")

        command = backend.build_command
        expected_bridging = File.join(Sensemaker::Paths.job_directory(bridge_job), "bridging_scores.csv")
        expected_output = File.join(Sensemaker::Paths.job_directory(job), "report.html")
        expected_input_dir = Sensemaker::Paths.job_directory(job)
        expected_config = job.artefacts.report_config_path

        expect(command).to include("node #{report_builder_folder.join("bin/cli.js")}")
        expect(command).to include("inline")
        expect(command).to include("--bridging_scores #{expected_bridging}")
        expect(command).to include("--summary #{summary_path}")
        expect(command).to include("--output #{expected_output}")
        expect(command).to include("--inputDir #{Shellwords.escape(expected_input_dir)}")
        expect(command).to include("--config #{Shellwords.escape(expected_config)}")
        expect(command).not_to include("--adapter")
        expect(command).not_to include("sensemaking-")
        expect(command).not_to include("venv/bin")
      end
    end

    describe "#cli_flags" do
      it "writes config.json with default title when run_options config is blank" do
        job.update!(run_options: {})
        conversation = instance_double(Sensemaker::Conversation)
        allow(job).to receive(:conversation).and_return(conversation)
        allow(conversation).to receive(:target_label).with(format: :full).and_return("Test Label")

        expected_config = job.artefacts.report_config_path
        flags = backend.cli_flags

        expect(flags["config"]).to eq(expected_config)
        expect(flags["inputDir"]).to eq(Sensemaker::Paths.job_directory(job))
        expect(JSON.parse(File.read(expected_config))).to eq("title" => "Test Label")
        expect(backend.build_command).to include("--config #{Shellwords.escape(expected_config)}")
      end

      it "writes config.json merging run_options and defaulting blank title" do
        job.update!(
          run_options: {
            "config" => {
              "title" => "",
              "logo" => "",
              "excluded_topics" => ["Other"]
            }
          }
        )
        conversation = instance_double(Sensemaker::Conversation)
        allow(job).to receive(:conversation).and_return(conversation)
        allow(conversation).to receive(:target_label).with(format: :full).and_return("Test Label")

        expected_config = job.artefacts.report_config_path
        flags = backend.cli_flags

        expect(flags["config"]).to eq(expected_config)
        expect(JSON.parse(File.read(expected_config))).to eq(
          "title" => "Test Label",
          "excluded_topics" => ["Other"]
        )
      end

      it "writes config.json preserving a custom title" do
        config = { "excluded_topics" => ["Other"], "title" => "Custom Title" }
        job.update!(run_options: { "config" => config })
        conversation = instance_double(Sensemaker::Conversation)
        allow(job).to receive(:conversation).and_return(conversation)
        allow(conversation).to receive(:target_label).with(format: :full).and_return("Test Label")

        expected_config = job.artefacts.report_config_path
        flags = backend.cli_flags

        expect(flags["config"]).to eq(expected_config)
        expect(flags["inputDir"]).to eq(Sensemaker::Paths.job_directory(job))
        expect(JSON.parse(File.read(expected_config))).to eq(config)
        expect(backend.build_command).to include("--config #{Shellwords.escape(expected_config)}")
      end
    end

    describe "#working_directory" do
      it "uses Rails.root so node_modules resolves" do
        expect(backend.working_directory).to eq(Rails.root)
      end
    end

    describe "#check_runtime_dependencies?" do
      before do
        allow(backend).to receive(:system).with("which node > /dev/null 2>&1").and_return(true)
      end

      it "returns true when node, package, summary, and bridging artefacts exist" do
        expect(backend.check_runtime_dependencies?).to be true
      end

      it "returns false when bridging scores are missing from the prep chain" do
        FileUtils.rm_f(File.join(Sensemaker::Paths.job_directory(bridge_job), "bridging_scores.csv"))
        expect(backend.check_runtime_dependencies?).to be false
        expect(job.error).to include("Bridging scores CSV")
      end

      it "returns false when the report-builder CLI is missing" do
        FileUtils.rm_f(report_builder_folder.join("bin/cli.js"))
        expect(backend.check_runtime_dependencies?).to be false
        expect(job.error).to include("sensemaking-report-builder CLI")
      end
    end
  end

  describe "proposition pipeline commands" do
    let(:sensemaker_folder) { Rails.root.join("tmp/sensemaker_test_folder") }
    let(:backend) { SensemakerExt::Backend::Python.new(job, runtime_config: runtime_config) }

    before do
      allow(Setting).to receive(:[]).and_call_original
      allow(Setting).to receive(:[]).with("llm.sensemaker_provider").and_return("VertexAI")
      allow(Setting).to receive(:[]).with("llm.sensemaker_model").and_return("gemini-2.5-flash-lite")
      allow(Setting).to receive(:[]).with("llm.sensemaker_fast_model").and_return(nil)
      allow(Llm::Config).to receive(:context).and_return(llm_context)
      allow(Sensemaker::Paths).to receive(:sensemaker_folder).and_return(sensemaker_folder)
      FileUtils.mkdir_p(sensemaker_folder.join("venv/bin"))
      %w[
        sensemaking-propositions
        sensemaking-refine-propositions
        sensemaking-world-model
      ].each do |cli|
        path = sensemaker_folder.join("venv/bin/#{cli}")
        File.write(path, "#!/bin/sh\n")
        File.chmod(0o755, path)
      end
    end

    describe "propositions" do
      let(:job) do
        create(:sensemaker_job,
               script: "propositions",
               user: user,
               analysable_type: "Debate",
               analysable_id: debate.id,
               input_file: "#{data_folder}/job-cat/categorized",
               additional_context: "Extra context")
      end

      before { FileUtils.mkdir_p(Sensemaker::Paths.job_directory(job)) }

      it "builds command with r1 input, output dir, LLM flags, and context" do
        command = backend.build_command
        expected_input = "#{data_folder}/job-cat/categorized_without_other_filtered.csv"
        expected_dir = Sensemaker::Paths.job_directory(job)

        expect(command).to include("sensemaking-propositions")
        expect(command).to include("--r1_input_file #{Shellwords.escape(expected_input)}")
        expect(command).to include("--output_dir #{Shellwords.escape(expected_dir)}")
        expect(command).to include("--adapter vertex")
        expect(command).to include("--model_name gemini-2.5-flash-lite")
        expect(command).to include("--additional_context #{Shellwords.escape("Extra context")}")
      end

      it "does not re-append filtered suffix when already present" do
        job.update!(input_file: "#{data_folder}/job-cat/categorized_without_other_filtered.csv")
        command = backend.build_command

        r1_input_file = Shellwords.escape("#{data_folder}/job-cat/categorized_without_other_filtered.csv")
        expect(command).to include("--r1_input_file #{r1_input_file}")
        expect(command).not_to include("filtered.csv_without_other_filtered.csv")
      end

      it "builds gemini adapter flags for Gemini API Studio" do
        allow(Setting).to receive(:[]).with("llm.sensemaker_provider").and_return("Gemini")
        allow(Setting).to receive(:[]).with("llm.sensemaker_model").and_return("gemini-2.5-pro")

        command = backend.build_command

        expect(command).to include("--adapter gemini")
        expect(command).to include("--api_key gemini-secret")
        expect(command).to include("--model_name gemini-2.5-pro")
        expect(command).not_to include("--provider")
        expect(command).not_to include("--vertex_project")
      end

      describe "#cli_flags" do
        it "returns structured flags for a vertex propositions command" do
          flags = backend.cli_flags
          expected_input = "#{data_folder}/job-cat/categorized_without_other_filtered.csv"
          expected_dir = Sensemaker::Paths.job_directory(job)

          expect(flags).to include(
            "adapter" => "vertex",
            "model_name" => "gemini-2.5-flash-lite",
            "vertex_project" => "sensemaker-466109",
            "vertex_location" => "global",
            "r1_input_file" => expected_input,
            "output_dir" => expected_dir,
            "additional_context" => "Extra context"
          )
          expect(flags).not_to have_key("api_key")
          expect(flags).not_to have_key("base_url")
        end
      end

      describe "#persistable_cli_flags" do
        it "keeps full flags including paths and context" do
          flags = backend.persistable_cli_flags
          expected_input = "#{data_folder}/job-cat/categorized_without_other_filtered.csv"
          expected_dir = Sensemaker::Paths.job_directory(job)

          expect(flags).to include(
            "adapter" => "vertex",
            "model_name" => "gemini-2.5-flash-lite",
            "vertex_project" => "sensemaker-466109",
            "r1_input_file" => expected_input,
            "output_dir" => expected_dir,
            "additional_context" => "Extra context"
          )
          expect(flags).not_to have_key("api_key")
        end

        it "redacts api_key for Gemini API Studio" do
          allow(Setting).to receive(:[]).with("llm.sensemaker_provider").and_return("Gemini")
          allow(Setting).to receive(:[]).with("llm.sensemaker_model").and_return("gemini-2.5-pro")

          flags = backend.persistable_cli_flags

          expect(flags).to include(
            "adapter" => "gemini",
            "model_name" => "gemini-2.5-pro",
            "api_key" => "[REDACTED]"
          )
          expect(backend.cli_flags).to include("api_key" => "gemini-secret")
        end
      end
    end

    describe "refine_propositions" do
      let(:pkl_path) { "#{data_folder}/job-props/world_model.pkl" }
      let(:job) do
        create(:sensemaker_job,
               script: "refine_propositions",
               user: user,
               analysable_type: "Debate",
               analysable_id: debate.id,
               input_file: pkl_path,
               additional_context: "Jury context")
      end

      before { FileUtils.mkdir_p(Sensemaker::Paths.job_directory(job)) }

      it "builds command with pickle paths, pav selection, and stage model flags" do
        command = backend.build_command
        expected_output = File.join(Sensemaker::Paths.job_directory(job), "refined_world_model.pkl")

        expect(command).to include("sensemaking-refine-propositions")
        expect(command).to include("--input_pkl #{Shellwords.escape(pkl_path)}")
        expect(command).to include("--output_pkl #{Shellwords.escape(expected_output)}")
        expect(command).to include("--run_pav_selection")
        expect(command).to include("--adapter vertex")
        expect(command).to include("--simulated_jury_model_name gemini-2.5-flash-lite")
        expect(command).to include("--nuanced_propositions_model_name gemini-2.5-flash-lite")
        expect(command).not_to include("--model_name")
        expect(command).to include("--additional_context #{Shellwords.escape("Jury context")}")
      end

      it "uses distinct fast and primary models when both are configured" do
        allow(Setting).to receive(:[]).with("llm.sensemaker_model").and_return("gemini-2.5-pro")
        allow(Setting).to receive(:[]).with("llm.sensemaker_fast_model")
          .and_return("gemini-2.5-flash-lite")

        command = backend.build_command

        expect(command).to include("--simulated_jury_model_name gemini-2.5-flash-lite")
        expect(command).to include("--nuanced_propositions_model_name gemini-2.5-pro")
        expect(command).not_to include("--model_name")
      end

      describe "#cli_flags" do
        it "includes both stage model keys when fast model is set" do
          allow(Setting).to receive(:[]).with("llm.sensemaker_model").and_return("gemini-2.5-pro")
          allow(Setting).to receive(:[]).with("llm.sensemaker_fast_model")
            .and_return("gemini-2.5-flash-lite")

          flags = backend.cli_flags

          expect(flags).to include(
            "simulated_jury_model_name" => "gemini-2.5-flash-lite",
            "nuanced_propositions_model_name" => "gemini-2.5-pro",
            "run_pav_selection" => true
          )
          expect(flags).not_to have_key("model_name")
        end
      end
    end

    describe "ranked_propositions" do
      let(:pkl_path) { "#{data_folder}/job-refine/refined_world_model.pkl" }
      let(:job) do
        create(:sensemaker_job,
               script: "ranked_propositions",
               user: user,
               analysable_type: "Debate",
               analysable_id: debate.id,
               input_file: pkl_path,
               additional_context: "")
      end

      before { FileUtils.mkdir_p(Sensemaker::Paths.job_directory(job)) }

      it "builds world-model export command without LLM flags" do
        command = backend.build_command
        expected_csv = File.join(
          Sensemaker::Paths.job_directory(job),
          "final_propositions_by_topic.csv"
        )

        expect(command).to include("sensemaking-world-model")
        expect(command).to include("--query all_by_topic")
        expect(command).to include("--output_format csv")
        expect(command).to include(Shellwords.escape(pkl_path))
        expect(command).to include("> #{Shellwords.escape(expected_csv)}")
        expect(command).not_to include("--adapter")
        expect(command).not_to include("--model_name")
      end
    end
  end
end
