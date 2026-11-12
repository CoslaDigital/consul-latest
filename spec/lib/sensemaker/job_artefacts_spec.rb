require "rails_helper"

describe Sensemaker::JobArtefacts do
  let(:user) { create(:user) }
  let(:debate) { create(:debate) }
  let(:job) do
    create(:sensemaker_job,
           analysable_type: "Debate",
           analysable_id: debate.id,
           script: "categorization_runner.ts",
           user: user,
           started_at: Time.current,
           additional_context: "Test context")
  end
  let(:artefacts) { Sensemaker::JobArtefacts.new(job) }

  shared_context "sensemaker paths stubbed" do
    let(:data_folder) { "/tmp/sensemaker_test_folder/data" }
    let(:job_dir) { "#{data_folder}/job-#{job.id}" }

    before do
      allow(Sensemaker::Paths).to receive(:sensemaker_data_folder).and_return(data_folder)
    end
  end

  describe "#output_file_name" do
    {
      "categorization_runner.ts" => "categorization-output.csv",
      "advanced_runner.ts" => "output",
      "runner.ts" => "output",
      "health_check_runner.ts" => "health-check.txt",
      "sensemaking-report-ui" => "report.html"
    }.each do |script, expected_name|
      it "returns the correct output file name for #{script}" do
        job.script = script
        expect(artefacts.output_file_name).to eq(expected_name)
      end
    end

    it "falls back for unknown scripts" do
      job.script = "unknown_runner.ts"
      expect(artefacts.output_file_name).to eq("output.csv")
    end
  end

  describe "#multiple_outputs?" do
    it "returns true for advanced_runner.ts and runner.ts" do
      job.script = "advanced_runner.ts"
      expect(artefacts.multiple_outputs?).to be true
      job.script = "runner.ts"
      expect(artefacts.multiple_outputs?).to be true
    end

    it "returns false for single output scripts" do
      job.script = "categorization_runner.ts"
      expect(artefacts.multiple_outputs?).to be false
      job.script = "health_check_runner.ts"
      expect(artefacts.multiple_outputs?).to be false
      job.script = "sensemaking-report-ui"
      expect(artefacts.multiple_outputs?).to be false
    end
  end

  describe "#job_directory" do
    include_context "sensemaker paths stubbed"

    it "returns the per-job directory under the data folder" do
      expect(artefacts.job_directory).to eq(job_dir)
    end
  end

  describe "#ensure_directory!" do
    include_context "sensemaker paths stubbed"

    it "creates the job directory" do
      expect(FileUtils).to receive(:mkdir_p).with(job_dir)
      artefacts.ensure_directory!
    end
  end

  describe "#report_config_path" do
    include_context "sensemaker paths stubbed"

    it "returns config.json under the job directory" do
      expect(artefacts.report_config_path).to eq("#{job_dir}/config.json")
    end
  end

  describe "#write_report_config" do
    include_context "sensemaker paths stubbed"

    it "creates the directory, writes pretty JSON, and returns the path" do
      config = { "title" => "Test Label", "excluded_topics" => ["Other"] }
      expect(FileUtils).to receive(:mkdir_p).with(job_dir)
      expect(File).to receive(:write).with(
        "#{job_dir}/config.json",
        JSON.pretty_generate(config)
      )

      expect(artefacts.write_report_config(config)).to eq("#{job_dir}/config.json")
    end
  end

  describe "#default_output_path" do
    include_context "sensemaker paths stubbed"

    {
      "categorization_runner.ts" => ->(jd) { "#{jd}/categorization-output.csv" },
      "advanced_runner.ts" => ->(jd) { "#{jd}/output" },
      "runner.ts" => ->(jd) { "#{jd}/output" }
    }.each do |script, expected_path_fn|
      it "returns the correct path for #{script}" do
        job.script = script
        expect(artefacts.default_output_path).to eq(expected_path_fn.call(job_dir))
      end
    end
  end

  describe "#relative_output_path" do
    let(:relative_data_folder) { "tmp/sensemaker_test_folder/data" }
    let(:relative_job_dir) { "#{relative_data_folder}/job-#{job.id}" }

    before do
      allow(Sensemaker::Paths).to receive(:sensemaker_relative_data_folder).and_return(relative_data_folder)
    end

    it "returns a path relative to Rails.root (no leading slash)" do
      job.script = "categorization_runner.ts"
      path = artefacts.relative_output_path
      expect(path).to eq("#{relative_job_dir}/categorization-output.csv")
      expect(path).not_to start_with("/")
    end

    {
      "advanced_runner.ts" => ->(rjd) { "#{rjd}/output" },
      "sensemaking-report-ui" => ->(rjd) { "#{rjd}/report.html" }
    }.each do |script, expected_path_fn|
      it "returns the correct relative path for #{script}" do
        job.script = script
        expect(artefacts.relative_output_path).to eq(expected_path_fn.call(relative_job_dir))
      end
    end
  end

  describe "#persisted_output_path" do
    [nil, ""].each do |blank_value|
      it "returns nil when persisted_output is #{blank_value.inspect}" do
        job.persisted_output = blank_value
        expect(artefacts.persisted_output_path).to be(nil)
      end
    end

    it "resolves relative persisted_output against Rails.root so path survives deploys" do
      relative_path = "tmp/sensemaker_test_folder/data/job-60/output"
      job.persisted_output = relative_path
      expect(artefacts.persisted_output_path).to eq(Rails.root.join(relative_path))
      expect(artefacts.persisted_output_path.to_s).to include(Rails.root.to_s)
    end
  end

  describe "#output_artefact_paths" do
    include_context "sensemaker paths stubbed"
    let(:base_path) { "#{job_dir}/output" }

    context "when persisted_output is not set" do
      it "uses default_output_path for single output scripts" do
        job.script = "categorization_runner.ts"
        expected_path = "#{job_dir}/categorization-output.csv"
        expect(artefacts.output_artefact_paths).to eq([expected_path])
      end

      it "uses default_output_path for advanced_runner.ts" do
        job.script = "advanced_runner.ts"
        expect(artefacts.output_artefact_paths).to eq([
          "#{base_path}-summary.json",
          "#{base_path}-topic-stats.json",
          "#{base_path}-comments-with-scores.json"
        ])
      end

      it "uses default_output_path for runner.ts" do
        job.script = "runner.ts"
        expect(artefacts.output_artefact_paths).to eq([
          "#{base_path}-summary.json",
          "#{base_path}-summary.html",
          "#{base_path}-summary.md",
          "#{base_path}-summaryAndSource.csv"
        ])
      end
    end

    context "when persisted_output is set" do
      let(:persisted_path) { "/historical/path/output" }

      before do
        job.persisted_output = persisted_path
      end

      it "uses resolved persisted_output_path (absolute) so File.exist? works after deploys" do
        job.script = "categorization_runner.ts"
        expect(artefacts.output_artefact_paths).to eq([persisted_path])
      end

      it "uses persisted_output for advanced_runner.ts" do
        job.script = "advanced_runner.ts"
        expect(artefacts.output_artefact_paths).to eq([
          "#{persisted_path}-summary.json",
          "#{persisted_path}-topic-stats.json",
          "#{persisted_path}-comments-with-scores.json"
        ])
      end

      it "uses persisted_output for runner.ts" do
        job.script = "runner.ts"
        expect(artefacts.output_artefact_paths).to eq([
          "#{persisted_path}-summary.json",
          "#{persisted_path}-summary.html",
          "#{persisted_path}-summary.md",
          "#{persisted_path}-summaryAndSource.csv"
        ])
      end

      context "when persisted_output is a relative path (post-deploy safe)" do
        let(:relative_path) { "vendor/sensemaking-tools/data/job-#{job.id}/output" }

        before do
          job.persisted_output = relative_path
        end

        it "returns absolute paths via persisted_output_path so complete? can find files" do
          job.script = "categorization_runner.ts"
          expected = Rails.root.join(relative_path).to_s
          expect(artefacts.output_artefact_paths).to eq([expected])
        end
      end
    end
  end

  describe "#complete?" do
    include_context "sensemaker paths stubbed"

    before do
      allow(File).to receive(:exist?).and_return(false)
    end

    context "when script has single output" do
      before do
        job.script = "categorization_runner.ts"
      end

      it "returns true when the output file exists" do
        output_path = "#{job_dir}/categorization-output.csv"
        allow(File).to receive(:exist?).with(output_path).and_return(true)
        expect(artefacts.complete?).to be true
      end

      it "returns false when the output file does not exist" do
        expect(artefacts.complete?).to be false
      end
    end

    shared_examples "complete for multi-output script" do |script_name, path_suffixes|
      before { job.script = script_name }

      it "returns true when all output files exist" do
        base_path = "#{job_dir}/output"
        path_suffixes.each do |suffix|
          allow(File).to receive(:exist?).with("#{base_path}#{suffix}").and_return(true)
        end
        expect(artefacts.complete?).to be true
      end

      it "returns false when not all output files exist" do
        base_path = "#{job_dir}/output"
        path_suffixes[0..-2].each do |suffix|
          allow(File).to receive(:exist?).with("#{base_path}#{suffix}").and_return(true)
        end
        allow(File).to receive(:exist?).with("#{base_path}#{path_suffixes.last}").and_return(false)
        expect(artefacts.complete?).to be false
      end
    end

    it_behaves_like "complete for multi-output script",
                    "advanced_runner.ts",
                    %w[-summary.json -topic-stats.json -comments-with-scores.json]

    it_behaves_like "complete for multi-output script",
                    "runner.ts",
                    %w[-summary.json -summary.html -summary.md -summaryAndSource.csv]
  end

  describe "#input_path" do
    include_context "sensemaker paths stubbed"

    it "returns the stored input_file when set" do
      job[:input_file] = "/custom/input.csv"
      expect(artefacts.input_path).to eq("/custom/input.csv")
    end

    it "defaults to categorization output for advanced_runner.ts when input_file is not set" do
      job.script = "advanced_runner.ts"
      job[:input_file] = nil
      expect(artefacts.input_path).to eq("#{job_dir}/categorization-output.csv")
    end

    it "defaults to advanced-output for report script when input_file is not set" do
      job.script = "sensemaking-report-ui"
      job[:input_file] = nil
      expect(artefacts.input_path).to eq("#{job_dir}/advanced-output")
    end

    it "defaults to input csv for other scripts when input_file is not set" do
      job.script = "runner.ts"
      job[:input_file] = nil
      expect(artefacts.input_path).to eq("#{job_dir}/input.csv")
    end
  end

  describe "#input_artefact_paths" do
    include_context "sensemaker paths stubbed"

    it "returns an empty array when input_path is blank" do
      job.script = "health_check_runner.ts"
      job[:input_file] = nil
      expect(artefacts.input_artefact_paths).to eq([])
    end

    it "returns a single path for single-input scripts" do
      job.script = "runner.ts"
      job[:input_file] = "/tmp/input.csv"
      expect(artefacts.input_artefact_paths).to eq([job[:input_file]])
    end

    it "returns derived JSON artefacts for sensemaking-report-ui" do
      job.script = "sensemaking-report-ui"
      job[:input_file] = "/tmp/output"

      expect(artefacts.input_artefact_paths).to eq([
        "#{job[:input_file]}-topic-stats.json",
        "#{job[:input_file]}-summary.json",
        "#{job[:input_file]}-comments-with-scores.json"
      ])
    end
  end

  describe "#existing_output_artefact_paths" do
    include_context "sensemaker paths stubbed"
    let(:base_path) { "#{job_dir}/output" }

    before do
      allow(File).to receive(:exist?).and_return(false)
    end

    it "returns only paths for which the file exists" do
      job.script = "runner.ts"
      existing_path = "#{base_path}-summary.json"
      allow(File).to receive(:exist?).with(existing_path).and_return(true)

      expect(artefacts.existing_output_artefact_paths).to eq([existing_path])
    end

    it "excludes paths for which the file does not exist" do
      job.script = "runner.ts"
      path1 = "#{base_path}-summary.json"
      path2 = "#{base_path}-summary.html"
      allow(File).to receive(:exist?).with(path1).and_return(true)
      allow(File).to receive(:exist?).with(path2).and_return(false)

      expect(artefacts.existing_output_artefact_paths).to eq([path1])
    end
  end

  describe "#existing_input_artefact_paths" do
    include_context "sensemaker paths stubbed"

    before do
      allow(File).to receive(:exist?).and_return(false)
    end

    it "returns only input artefacts that exist" do
      existing_path = "/tmp/input-existing.csv"
      allow(File).to receive(:exist?).with(existing_path).and_return(true)
      job.script = "runner.ts"
      job[:input_file] = existing_path

      expect(artefacts.existing_input_artefact_paths).to eq([existing_path])
    end

    it "returns only existing derived input artefacts for sensemaking-report-ui" do
      job.script = "sensemaking-report-ui"
      job[:input_file] = "/tmp/output"
      existing = "#{job[:input_file]}-summary.json"
      missing_1 = "#{job[:input_file]}-topic-stats.json"
      missing_2 = "#{job[:input_file]}-comments-with-scores.json"

      allow(File).to receive(:exist?).with(existing).and_return(true)
      allow(File).to receive(:exist?).with(missing_1).and_return(false)
      allow(File).to receive(:exist?).with(missing_2).and_return(false)

      expect(artefacts.existing_input_artefact_paths).to eq([existing])
    end

    context "with additional_input_scripts from the prep tree" do
      let(:alt_summary_dir) { "#{data_folder}/job-alt-summary" }
      let(:alt_bridge_dir) { "#{data_folder}/job-alt-bridge" }
      let(:alt_categorize_dir) { "#{data_folder}/job-alt-categorize" }
      let(:summary_base) { File.join(alt_summary_dir, "report_data") }
      let(:summary_json) { "#{summary_base}.json" }
      let(:bridging_csv) { File.join(alt_bridge_dir, "bridging_scores.csv") }
      let(:categorized) { File.join(alt_categorize_dir, "categorized_with_other.csv") }

      before do
        allow(Sensemaker::ScriptRegistry).to receive(:artefact_config).and_call_original
        allow(Sensemaker::ScriptRegistry).to receive(:artefact_config).with("alt_report").and_return(
          output_basename: ->(_job) { "report.html" },
          output_suffixes: [],
          default_input_path: nil,
          input_suffixes: %w[.json],
          additional_input_scripts: %w[alt_bridge]
        )
        allow(Sensemaker::ScriptRegistry).to receive(:artefact_config).with("alt_summary").and_return(
          output_basename: ->(_job) { "report_data" },
          output_suffixes: %w[.json _with_opinions.json],
          default_input_path: nil,
          input_suffixes: [],
          additional_input_scripts: []
        )
        allow(Sensemaker::ScriptRegistry).to receive(:artefact_config).with("alt_bridge").and_return(
          output_basename: ->(_job) { "bridging_scores.csv" },
          output_suffixes: [],
          default_input_path: nil,
          input_suffixes: [],
          additional_input_scripts: []
        )
        allow(Sensemaker::ScriptRegistry).to receive(:artefact_config).with("alt_categorize").and_return(
          output_basename: ->(_job) { "categorized" },
          output_suffixes: %w[
            _with_other.csv
            _with_other_filtered.csv
            _without_other.csv
            _without_other_filtered.csv
            _with_other_topic_tree.txt
          ],
          default_input_path: nil,
          input_suffixes: [],
          additional_input_scripts: []
        )
      end

      it "lists only direct inputs and configured additional prep outputs" do
        allow(File).to receive(:exist?).and_call_original
        allow(Sensemaker::Paths).to receive(:job_directory) do |j|
          "#{data_folder}/job-#{j.id}"
        end

        parent = create(:sensemaker_job,
                        analysable_type: "Debate",
                        analysable_id: debate.id,
                        script: "alt_report",
                        user: user,
                        started_at: Time.current,
                        input_file: summary_base)
        alt_summary = create(:sensemaker_job,
                             parent_job: parent,
                             analysable_type: "Debate",
                             analysable_id: debate.id,
                             script: "alt_summary",
                             user: user,
                             started_at: Time.current)
        alt_bridge = create(:sensemaker_job,
                            parent_job: alt_summary,
                            analysable_type: "Debate",
                            analysable_id: debate.id,
                            script: "alt_bridge",
                            user: user,
                            started_at: Time.current)
        alt_categorize = create(:sensemaker_job,
                                parent_job: alt_bridge,
                                analysable_type: "Debate",
                                analysable_id: debate.id,
                                script: "alt_categorize",
                                user: user,
                                started_at: Time.current)

        allow(Sensemaker::Paths).to receive(:job_directory).with(alt_summary).and_return(alt_summary_dir)
        allow(Sensemaker::Paths).to receive(:job_directory).with(alt_bridge).and_return(alt_bridge_dir)
        allow(Sensemaker::Paths).to receive(:job_directory).with(alt_categorize)
          .and_return(alt_categorize_dir)
        allow(Sensemaker::Paths).to receive(:job_directory).with(parent).and_return(
          "#{data_folder}/job-#{parent.id}"
        )

        FileUtils.mkdir_p([alt_summary_dir, alt_bridge_dir, alt_categorize_dir])
        File.write(summary_json, "{}")
        File.write(File.join(alt_summary_dir, "report_data_with_opinions.json"), "{}")
        File.write(bridging_csv, "a,b\n")
        File.write(categorized, "a,b\n")
        File.write(File.join(alt_categorize_dir, "categorized_with_other_filtered.csv"), "a,b\n")
        File.write(File.join(alt_categorize_dir, "categorized_without_other.csv"), "a,b\n")
        File.write(File.join(alt_categorize_dir, "categorized_without_other_filtered.csv"), "a,b\n")
        File.write(File.join(alt_categorize_dir, "categorized_with_other_topic_tree.txt"), "tree")

        paths = Sensemaker::JobArtefacts.new(parent).existing_input_artefact_paths
        expect(paths).to contain_exactly(summary_json, bridging_csv)
        expect(paths).not_to include(categorized)
      end
    end
  end


  describe "#cleanup" do
    include_context "sensemaker paths stubbed"

    before do
      allow(FileUtils).to receive_messages(rm_rf: [job_dir], rm_f: true)
      allow(Dir).to receive(:exist?).and_call_original
      allow(Dir).to receive(:exist?).with(job_dir).and_return(true)
    end

    it "removes the job directory" do
      expect(FileUtils).to receive(:rm_rf).with(job_dir)
      artefacts.cleanup
    end

    context "when persisted_output is present outside the job directory and file exists" do
      before do
        job.persisted_output = "/path/to/output.txt"
        allow(File).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).with(Rails.root.join("/path/to/output.txt")).and_return(true)
      end

      it "removes the persisted output file using resolved path (persisted_output_path)" do
        resolved = Rails.root.join("/path/to/output.txt")
        expect(FileUtils).to receive(:rm_f).with(resolved)

        artefacts.cleanup
      end
    end

    context "when persisted_output is inside the job directory" do
      before do
        job.persisted_output = "#{job_dir}/report.html"
        allow(File).to receive(:exist?).and_return(true)
      end

      it "does not separately remove persisted output already covered by rm_rf" do
        expect(FileUtils).not_to receive(:rm_f)
        artefacts.cleanup
      end
    end

    context "when persisted_output is nil" do
      before do
        job.persisted_output = nil
      end

      it "does not attempt to remove a persisted output file" do
        expect(FileUtils).not_to receive(:rm_f).with("/path/to/output.txt")
        artefacts.cleanup
      end
    end

    it "handles errors gracefully" do
      allow(FileUtils).to receive(:rm_rf).and_raise(StandardError.new("File system error"))

      expect(artefacts.cleanup).to be(nil)
    end
  end

  describe "preparation helpers" do
    include_context "sensemaker paths stubbed"

    let(:report_job) do
      create(:sensemaker_job,
             analysable_type: "Debate",
             analysable_id: debate.id,
             script: "sensemaking-report-ui",
             user: user,
             started_at: Time.current)
    end
    let(:report_artefacts) { Sensemaker::JobArtefacts.new(report_job) }

    def write_job_output(prep_job, relative_name, content = "x")
      dir = Sensemaker::Paths.job_directory(prep_job)
      FileUtils.mkdir_p(dir)
      path = File.join(dir, relative_name)
      File.write(path, content)
      path
    end

    context "with no preparation jobs" do
      it "returns no jobs or outputs" do
        expect(report_artefacts.preparation_jobs).to eq([])
        expect(report_artefacts.preparation_output_paths_by_script).to eq({})
        expect(report_artefacts.preparation_outputs_for("categorization_runner.ts")).to eq([])
        expect(report_artefacts.preparation_output_for("categorization_runner.ts")).to be(nil)
      end
    end

    context "with a nested prep tree and files on disk" do
      let!(:summary_job) do
        create(:sensemaker_job,
               parent_job: report_job,
               analysable_type: "Debate",
               analysable_id: debate.id,
               script: "runner.ts",
               user: user,
               started_at: Time.current)
      end
      let!(:bridge_job) do
        create(:sensemaker_job,
               parent_job: summary_job,
               analysable_type: "Debate",
               analysable_id: debate.id,
               script: "categorization_runner.ts",
               user: user,
               started_at: Time.current)
      end
      let!(:summary_json) { write_job_output(summary_job, "output-summary.json", "{}") }
      let!(:summary_html) { write_job_output(summary_job, "output-summary.html", "<html>") }
      let!(:bridge_csv) do
        write_job_output(bridge_job, "categorization-output.csv", "a,b\n")
      end

      before do
        allow(Sensemaker::Paths).to receive(:sensemaker_data_folder).and_return(data_folder)
        allow(Sensemaker::Paths).to receive(:job_directory) do |j|
          "#{data_folder}/job-#{j.id}"
        end
      end

      it "lists preparation jobs in BFS order" do
        expect(report_artefacts.preparation_jobs).to eq([summary_job, bridge_job])
      end

      it "maps scripts to existing output paths" do
        by_script = report_artefacts.preparation_output_paths_by_script
        expect(by_script["runner.ts"]).to include(summary_json, summary_html)
        expect(by_script["categorization_runner.ts"]).to eq([bridge_csv])
      end

      it "returns all outputs for a multi-output script" do
        expect(report_artefacts.preparation_outputs_for("runner.ts")).to include(
          summary_json, summary_html
        )
      end

      it "returns the first existing output for a script" do
        expect(report_artefacts.preparation_output_for("categorization_runner.ts")).to eq(bridge_csv)
      end

      it "omits scripts whose output files are missing" do
        FileUtils.rm_f(bridge_csv)
        expect(report_artefacts.preparation_outputs_for("categorization_runner.ts")).to eq([])
        expect(report_artefacts.preparation_output_for("categorization_runner.ts")).to be(nil)
      end

      it "exposes preparation outputs via existing_preparation_output_artefact_paths" do
        expect(report_artefacts.existing_preparation_output_artefact_paths).to include(
          summary_json, summary_html, bridge_csv
        )
      end
    end
  end
end
