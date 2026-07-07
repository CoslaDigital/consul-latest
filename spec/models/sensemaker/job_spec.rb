require "rails_helper"

describe Sensemaker::Job do
  let(:user) { create(:user) }
  let(:debate) { create(:debate) }
  let(:job) do
    create(:sensemaker_job,
           analysable_type: "Debate",
           analysable_id: debate.id,
           script: "categorize",
           user: user,
           started_at: Time.current,
           additional_context: "Test context")
  end

  shared_context "sensemaker paths stubbed" do
    let(:data_folder) { "/tmp/sensemaker_test_folder/data" }
    let(:relative_data_folder) { "tmp/sensemaker_test_folder/data" }

    before do
      allow(Sensemaker::Paths).to receive_messages(sensemaker_data_folder: data_folder,
                                                   sensemaker_relative_data_folder: relative_data_folder)
    end
  end

  describe "validations" do
    it "is valid with valid attributes" do
      expect(job).to be_valid
    end

    it "requires analysable_type" do
      job.analysable_type = nil
      expect(job).not_to be_valid
    end

    it "requires analysable_id for non-Proposal types" do
      job.analysable_id = nil
      expect(job).not_to be_valid
    end

    it "allows nil analysable_id for Proposal type" do
      job.analysable_type = "Proposal"
      job.analysable_id = nil
      expect(job).to be_valid
    end

    it "rejects unknown script values" do
      job.script = "runner.ts"
      expect(job).not_to be_valid
      expect(job.errors[:script]).to be_present
    end

    it "allows nil script" do
      job.script = nil
      expect(job).to be_valid
    end

    describe "#publishing_is_allowed" do
      let(:data_folder) { "/tmp/sensemaker_test_folder/data" }

      before do
        allow(Sensemaker::Paths).to receive(:sensemaker_data_folder).and_return(data_folder)
        allow(File).to receive(:exist?).and_return(false)
        job.published = false
      end

      context "when job is publishable" do
        before do
          job.script = "report_ui"
          job.finished_at = Time.current
          job.error = nil
          output_path = "#{data_folder}/job-#{job.id}/report.html"
          allow(File).to receive(:exist?).with(output_path).and_return(true)
        end

        it "allows publishing when changing from false to true" do
          job.published = true
          expect(job).to be_valid
        end
      end

      context "when job is not publishable" do
        it "adds validation error when published is changed to true" do
          # Set up a job that is not publishable (any condition fails)
          job.script = "categorize"
          job.finished_at = Time.current
          job.error = nil
          job.published = true

          expect(job).not_to be_valid
          expect(job.errors[:published]).to be_present
        end
      end

      context "when job is already published" do
        before do
          job.published = true
          job.save!(validate: false) # Save without validation to set initial state
        end

        it "does not validate when already published" do
          job.script = "categorize"
          job.finished_at = nil
          expect(job).to be_valid
        end
      end

      context "when job is not published" do
        it "does not validate publishable status" do
          job.script = "categorize"
          job.finished_at = nil
          job.published = false
          expect(job).to be_valid
        end
      end
    end
  end

  describe "associations" do
    it "belongs to a user" do
      expect(job.user).to eq(user)
    end
  end

  describe ".for_analysable" do
    context "when record is a Budget" do
      let(:budget) { create(:budget) }
      let!(:published_budget_job) do
        j = create(:sensemaker_job, analysable_type: "Budget", analysable_id: budget.id, published: false)
        j.update_column(:published, true)
        j
      end
      let!(:unpublished_budget_job) do
        create(:sensemaker_job, analysable_type: "Budget", analysable_id: budget.id, published: false)
      end
      let!(:other_budget_job) do
        j = create(:sensemaker_job,
                   analysable_type: "Budget",
                   analysable_id: create(:budget).id,
                   published: false)
        j.update_column(:published, true)
        j
      end

      it "with published_only: true returns only published jobs for that budget" do
        scope = Sensemaker::Job.for_analysable(budget, published_only: true)
        expect(scope).to include(published_budget_job)
        expect(scope).not_to include(unpublished_budget_job)
        expect(scope).not_to include(other_budget_job)
      end

      it "with published_only: false returns all jobs for that budget" do
        scope = Sensemaker::Job.for_analysable(budget, published_only: false)
        expect(scope).to include(published_budget_job)
        expect(scope).to include(unpublished_budget_job)
        expect(scope).not_to include(other_budget_job)
      end
    end

    context "when record is a Debate (else branch)" do
      let(:debate) { create(:debate) }
      let!(:published_debate_job) do
        j = create(:sensemaker_job, analysable_type: "Debate", analysable_id: debate.id, published: false)
        j.update_column(:published, true)
        j
      end
      let!(:unpublished_debate_job) do
        create(:sensemaker_job, analysable_type: "Debate", analysable_id: debate.id, published: false)
      end

      it "with published_only: true returns only published jobs for that record" do
        scope = Sensemaker::Job.for_analysable(debate, published_only: true)
        expect(scope).to include(published_debate_job)
        expect(scope).not_to include(unpublished_debate_job)
      end

      it "with published_only: false returns all jobs for that record" do
        scope = Sensemaker::Job.for_analysable(debate, published_only: false)
        expect(scope).to include(published_debate_job)
        expect(scope).to include(unpublished_debate_job)
      end
    end

    context "when record is Proposal (all proposals)" do
      let!(:all_proposals_job) do
        j = create(:sensemaker_job, analysable_type: "Proposal", analysable_id: nil, published: false)
        j.update_column(:published, true)
        j
      end
      let!(:specific_proposal_job) do
        j = create(:sensemaker_job,
                   analysable_type: "Proposal",
                   analysable_id: create(:proposal).id,
                   published: false)
        j.update_column(:published, true)
        j
      end

      it "with published_only: true returns only published jobs with nil analysable_id" do
        scope = Sensemaker::Job.for_analysable(Proposal, published_only: true)
        expect(scope).to include(all_proposals_job)
        expect(scope).not_to include(specific_proposal_job)
      end

      it "with published_only: false returns all jobs with nil analysable_id" do
        unpublished = create(:sensemaker_job,
                             analysable_type: "Proposal",
                             analysable_id: nil,
                             published: false)
        scope = Sensemaker::Job.for_analysable(Proposal, published_only: false)
        expect(scope).to include(all_proposals_job)
        expect(scope).to include(unpublished)
        expect(scope).not_to include(specific_proposal_job)
      end
    end

    context "when record is a Poll" do
      let(:poll) { create(:poll) }
      let!(:published_poll_job) do
        j = create(:sensemaker_job, analysable_type: "Poll", analysable_id: poll.id, published: false)
        j.update_column(:published, true)
        j
      end
      let!(:unpublished_poll_job) do
        create(:sensemaker_job, analysable_type: "Poll", analysable_id: poll.id, published: false)
      end

      it "with published_only: false returns all jobs for that poll" do
        scope = Sensemaker::Job.for_analysable(poll, published_only: false)
        expect(scope).to include(published_poll_job)
        expect(scope).to include(unpublished_poll_job)
      end
    end
  end

  describe "instance methods" do
    describe "#work_dir" do
      include_context "sensemaker paths stubbed"

      it "returns a flat per-job directory under the data folder" do
        expect(job.work_dir).to eq("#{data_folder}/job-#{job.id}")
      end
    end

    describe "#has_multiple_outputs?" do
      it "returns true for report_text" do
        job.script = "report_text"
        expect(job.has_multiple_outputs?).to be true
      end

      it "returns false for single output scripts" do
        %w[categorize bridge_scores health_check report_ui].each do |script_name|
          job.script = script_name
          expect(job.has_multiple_outputs?).to be false
        end
      end
    end

    describe "#output_file_name" do
      {
        "categorize" => "categorized_without_other_filtered.csv",
        "bridge_scores" => "bridging_scores.csv",
        "report_text" => "report_data.json",
        "health_check" => "health-check.txt",
        "report_ui" => "report.html",
        "propositions" => "world_model.pkl",
        "refine_propositions" => "refined_world_model.pkl",
        "ranked_propositions" => "final_propositions_by_topic.csv"
      }.each do |script, basename|
        it "returns the primary artefact basename for #{script}" do
          job.script = script
          expect(job.output_file_name).to eq(basename)
        end
      end
    end

    describe "#primary_artefact_path" do
      include_context "sensemaker paths stubbed"

      it "joins work_dir with output_file_name" do
        expect(job.primary_artefact_path).to eq(
          "#{data_folder}/job-#{job.id}/categorized_without_other_filtered.csv"
        )
      end
    end

    describe "#started?" do
      it "returns true when started_at is present" do
        expect(job.started?).to be true
      end

      it "returns false when started_at is nil" do
        job.started_at = nil
        expect(job.started?).to be false
      end
    end

    describe "#finished?" do
      it "returns true when finished_at is present" do
        job.finished_at = Time.current
        expect(job.finished?).to be true
      end

      it "returns false when finished_at is nil" do
        expect(job.finished?).to be false
      end
    end

    describe "#cancelled?" do
      it "returns true when finished_at is present and error is 'Cancelled'" do
        job.finished_at = Time.current
        job.error = "Cancelled"
        expect(job.cancelled?).to be true
      end
    end

    describe "cancel!" do
      it "updates the job with finished_at and error 'Cancelled'" do
        job.cancel!
        expect(job.finished_at).to be_present
        expect(job.error).to eq("Cancelled")
      end
    end

    describe "#errored?" do
      it "returns true when error is present" do
        job.error = "Some error occurred"
        expect(job.errored?).to be true
      end

      it "returns false when error is nil" do
        expect(job.errored?).to be false
      end
    end

    describe "#default_output_path" do
      include_context "sensemaker paths stubbed"

      it "returns primary_artefact_path" do
        job.script = "bridge_scores"
        expect(job.default_output_path).to eq(
          "#{data_folder}/job-#{job.id}/bridging_scores.csv"
        )
      end
    end

    describe "#relative_output_path" do
      include_context "sensemaker paths stubbed"

      it "returns a path relative to Rails.root (no leading slash)" do
        path = job.relative_output_path
        expect(path).to eq(
          "#{relative_data_folder}/job-#{job.id}/categorized_without_other_filtered.csv"
        )
        expect(path).not_to start_with("/")
      end
    end

    describe "#persisted_output_path" do
      [nil, ""].each do |blank_value|
        it "returns nil when persisted_output is #{blank_value.inspect}" do
          job.persisted_output = blank_value
          expect(job.persisted_output_path).to be(nil)
        end
      end

      it "resolves relative persisted_output against Rails.root so path survives deploys" do
        relative_path = "tmp/sensemaker_test_folder/data/job-60/report_data.json"
        job.persisted_output = relative_path
        expect(job.persisted_output_path).to eq(Rails.root.join(relative_path))
        expect(job.persisted_output_path.to_s).to include(Rails.root.to_s)
      end
    end

    describe "#output_artefact_paths" do
      include_context "sensemaker paths stubbed"
      let(:work_dir) { "#{data_folder}/job-#{job.id}" }

      context "when persisted_output is not set" do
        it "returns the primary artefact path for categorize" do
          job.script = "categorize"
          expect(job.output_artefact_paths).to eq([
            "#{work_dir}/categorized_without_other_filtered.csv"
          ])
        end

        it "includes optional secondary files for report_text" do
          job.script = "report_text"
          expect(job.output_artefact_paths).to eq([
            "#{work_dir}/report_data.json",
            "#{work_dir}/report_data_with_opinions.json"
          ])
        end
      end

      context "when persisted_output is set" do
        let(:persisted_path) { "/historical/path/job-#{job.id}/report_data.json" }

        before do
          job.persisted_output = persisted_path
        end

        it "uses the directory of persisted_output_path for siblings" do
          job.script = "report_text"
          expect(job.output_artefact_paths).to eq([
            persisted_path,
            "/historical/path/job-#{job.id}/report_data_with_opinions.json"
          ])
        end

        context "when persisted_output is a relative path (post-deploy safe)" do
          let(:relative_path) { "vendor/sensemaking-tools/data/job-#{job.id}/report_data.json" }

          before do
            job.persisted_output = relative_path
          end

          it "returns absolute paths via persisted_output_path so has_outputs? can find files" do
            job.script = "report_text"
            expected = Rails.root.join(relative_path).to_s
            opinions = File.join(File.dirname(relative_path), "report_data_with_opinions.json")
            expect(job.output_artefact_paths).to eq([
              expected,
              Rails.root.join(opinions).to_s
            ])
          end
        end
      end
    end

    describe "#existing_output_artefact_paths" do
      include_context "sensemaker paths stubbed"
      let(:base_path) { "#{data_folder}/output-#{job.id}" }

      before do
        allow(File).to receive(:exist?).and_return(false)
      end

      it "returns only paths for which the file exists" do
        job.script = "bridge_scores"
        existing_path = "#{data_folder}/job-#{job.id}/bridging_scores.csv"
        allow(File).to receive(:exist?).with(existing_path).and_return(true)

        expect(job.existing_output_artefact_paths).to eq([existing_path])
      end

      it "excludes paths for which the file does not exist" do
        job.script = "bridge_scores"
        existing_path = "#{data_folder}/job-#{job.id}/bridging_scores.csv"
        missing_path = "#{data_folder}/job-#{job.id}/other.csv"
        allow(File).to receive(:exist?).with(existing_path).and_return(true)
        allow(File).to receive(:exist?).with(missing_path).and_return(false)

        expect(job.existing_output_artefact_paths).to eq([existing_path])
      end
    end

    describe "#input_artefact_paths" do
      it "returns an empty array when input_file is blank" do
        allow(job).to receive(:input_file).and_return("")
        expect(job.input_artefact_paths).to eq([])
      end

      it "returns a single path when input_file is set" do
        job.script = "report_text"
        job[:input_file] = "/tmp/input-#{job.id}.csv"
        expect(job.input_artefact_paths).to eq(["/tmp/input-#{job.id}.csv"])
      end
    end

    describe "#existing_input_artefact_paths" do
      before do
        allow(File).to receive(:exist?).and_return(false)
      end

      it "returns only input artefacts that exist" do
        existing_path = "/tmp/input-existing-#{job.id}.csv"
        allow(File).to receive(:exist?).with(existing_path).and_return(true)
        job.script = "bridge_scores"
        job[:input_file] = existing_path

        expect(job.existing_input_artefact_paths).to eq([existing_path])
      end
    end

    describe "#has_outputs?" do
      include_context "sensemaker paths stubbed"

      before do
        allow(File).to receive(:exist?).and_return(false)
      end

      context "when script has a single required output" do
        before do
          job.script = "categorize"
        end

        it "returns true when the primary artefact exists" do
          output_path = "#{data_folder}/job-#{job.id}/categorized_without_other_filtered.csv"
          allow(File).to receive(:exist?).with(output_path).and_return(true)
          expect(job.has_outputs?).to be true
        end

        it "returns false when the primary artefact does not exist" do
          expect(job.has_outputs?).to be false
        end
      end

      context "when script is report_text" do
        before { job.script = "report_text" }

        it "returns true when only report_data.json exists" do
          primary = "#{data_folder}/job-#{job.id}/report_data.json"
          allow(File).to receive(:exist?).with(primary).and_return(true)
          expect(job.has_outputs?).to be true
        end

        it "returns false when only the optional opinions file exists" do
          optional = "#{data_folder}/job-#{job.id}/report_data_with_opinions.json"
          allow(File).to receive(:exist?).with(optional).and_return(true)
          expect(job.has_outputs?).to be false
        end
      end

      context "when script is ranked_propositions" do
        before { job.script = "ranked_propositions" }

        it "returns true when final_propositions_by_topic.csv exists" do
          output_path = "#{data_folder}/job-#{job.id}/final_propositions_by_topic.csv"
          allow(File).to receive(:exist?).with(output_path).and_return(true)
          expect(job.has_outputs?).to be true
        end

        it "returns false when the CSV does not exist" do
          expect(job.has_outputs?).to be false
        end
      end
    end

    describe "#world_model_pkl and #refined_world_model_pkl" do
      include_context "sensemaker paths stubbed"

      it "returns paths under work_dir" do
        expect(job.world_model_pkl).to eq("#{data_folder}/job-#{job.id}/world_model.pkl")
        expect(job.refined_world_model_pkl).to eq("#{data_folder}/job-#{job.id}/refined_world_model.pkl")
      end
    end

    describe "#publishable?" do
      include_context "sensemaker paths stubbed"

      before do
        allow(File).to receive(:exist?).and_return(false)
      end

      context "when script is report_ui" do
        before do
          job.script = "report_ui"
          job.finished_at = Time.current
          job.error = nil
        end

        it "returns true when all conditions are met" do
          output_path = "#{data_folder}/job-#{job.id}/report.html"
          allow(File).to receive(:exist?).with(output_path).and_return(true)
          expect(job.publishable?).to be true
        end

        it "returns false when job is not finished" do
          job.finished_at = nil
          output_path = "#{data_folder}/job-#{job.id}/report.html"
          allow(File).to receive(:exist?).with(output_path).and_return(true)
          expect(job.publishable?).to be false
        end

        it "returns false when job has errors" do
          job.error = "Some error occurred"
          output_path = "#{data_folder}/job-#{job.id}/report.html"
          allow(File).to receive(:exist?).with(output_path).and_return(true)
          expect(job.publishable?).to be false
        end

        it "returns false when job has no outputs" do
          expect(job.publishable?).to be false
        end
      end

      context "when script is not publishable" do
        before do
          job.finished_at = Time.current
          job.error = nil
        end

        it "returns false for categorize even when outputs exist" do
          job.script = "categorize"
          output_path = "#{data_folder}/job-#{job.id}/categorized_without_other_filtered.csv"
          allow(File).to receive(:exist?).with(output_path).and_return(true)
          expect(job.publishable?).to be false
        end

        it "returns false for bridge_scores even when outputs exist" do
          job.script = "bridge_scores"
          output_path = "#{data_folder}/job-#{job.id}/bridging_scores.csv"
          allow(File).to receive(:exist?).with(output_path).and_return(true)
          expect(job.publishable?).to be false
        end

        it "returns false for report_text even when outputs exist" do
          job.script = "report_text"
          output_path = "#{data_folder}/job-#{job.id}/report_data.json"
          allow(File).to receive(:exist?).with(output_path).and_return(true)
          expect(job.publishable?).to be false
        end

        it "returns false for health_check even when outputs exist" do
          job.script = "health_check"
          output_path = "#{data_folder}/job-#{job.id}/health-check.txt"
          allow(File).to receive(:exist?).with(output_path).and_return(true)
          expect(job.publishable?).to be false
        end
      end
    end

    describe "input path helpers" do
      include_context "sensemaker paths stubbed"

      it "returns default_input_csv under work_dir" do
        expect(job.default_input_csv).to eq("#{data_folder}/job-#{job.id}/input.csv")
      end

      it "returns categorize_output_csv for this job's work_dir" do
        expect(job.categorize_output_csv).to eq(
          "#{data_folder}/job-#{job.id}/categorized_without_other_filtered.csv"
        )
      end

      it "returns bridge_scores_csv for bridge_scores script layout" do
        job.script = "bridge_scores"
        expect(job.bridge_scores_csv).to eq("#{data_folder}/job-#{job.id}/bridging_scores.csv")
      end
    end

    describe "#cleanup_associated_files" do
      include_context "sensemaker paths stubbed"

      before do
        allow(FileUtils).to receive_messages(rm_f: true, rm_rf: true)
        allow(File).to receive(:directory?).and_return(false)
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
      end

      it "removes the work_dir with rm_rf when it exists" do
        work_dir_path = "#{data_folder}/job-#{job.id}"
        allow(File).to receive(:directory?).with(work_dir_path).and_return(true)
        expect(FileUtils).to receive(:rm_rf).with(work_dir_path)

        job.send(:cleanup_work_dir)
      end

      describe "#cleanup_persisted_output" do
        context "when persisted_output is present and file exists" do
          before do
            job.persisted_output = "/path/to/output.txt"
            allow(File).to receive(:exist?).and_return(false)
            allow(File).to receive(:exist?).with(Rails.root.join("/path/to/output.txt")).and_return(true)
          end

          it "removes the persisted output file using resolved path (persisted_output_path)" do
            resolved = Rails.root.join("/path/to/output.txt")
            expect(FileUtils).to receive(:rm_f).with(resolved)

            job.send(:cleanup_persisted_output)
          end
        end

        context "when persisted_output is nil" do
          before do
            job.persisted_output = nil
          end

          it "does not attempt to remove any file" do
            expect(FileUtils).not_to receive(:rm_f)

            job.send(:cleanup_persisted_output)
          end
        end
      end

      it "logs cleanup results" do
        expect(Rails.logger).to receive(:info).with(/Cleaned up files for job #{job.id}/)

        job.send(:cleanup_associated_files)
      end

      it "handles errors gracefully" do
        allow(job).to receive(:cleanup_work_dir).and_raise(StandardError.new("File system error"))

        expect(Rails.logger).to receive(:warn).with(/Failed to cleanup files for job #{job.id}/)

        result = job.send(:cleanup_associated_files)
        expect(result).to be(nil)
      end
    end
  end

  describe "callbacks" do
    describe "before_save :set_persisted_output_if_successful" do
      include_context "sensemaker paths stubbed"

      before do
        allow(File).to receive(:exist?).and_return(false)
      end

      it "sets persisted_output to relative_primary_artefact_path when primary artefact exists" do
        primary = job.primary_artefact_path
        allow(File).to receive(:exist?).with(primary).and_return(true)

        job.finished_at = Time.current
        job.error = nil
        job.save!

        expect(job.persisted_output).to eq(job.relative_primary_artefact_path)
        expect(job.persisted_output).not_to start_with("/")
      end

      it "does not set persisted_output when primary artefact is missing" do
        job.finished_at = Time.current
        job.error = nil
        job.save!

        expect(job.persisted_output).to be(nil)
      end

      context "when persisted_output is already set" do
        it "does not overwrite existing persisted_output" do
          existing_path = "existing/path/report_data.json"
          job.persisted_output = existing_path
          allow(File).to receive(:exist?).with(job.primary_artefact_path).and_return(true)

          job.finished_at = Time.current
          job.error = nil
          job.save!

          expect(job.persisted_output).to eq(existing_path)
        end
      end

      context "when job is not finished" do
        it "does not set persisted_output" do
          job.finished_at = nil
          job.error = nil
          job.save!

          expect(job.persisted_output).to be(nil)
        end
      end

      context "when job has an error" do
        it "does not set persisted_output" do
          job.finished_at = Time.current
          job.error = "Some error occurred"
          job.save!

          expect(job.persisted_output).to be(nil)
        end
      end
    end

    describe "after_destroy" do
      include_context "sensemaker paths stubbed"

      before do
        allow(FileUtils).to receive_messages(rm_f: true, rm_rf: true)
        allow(File).to receive(:directory?).and_return(false)
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
      end

      it "calls cleanup_associated_files when job is destroyed" do
        expect(job).to receive(:cleanup_associated_files)
        job.destroy!
      end

      it "continues with destruction even if cleanup fails" do
        expect(job).to receive(:cleanup_work_dir)
        allow(job).to receive(:cleanup_work_dir).and_raise(StandardError.new("Bork"))

        expect { job.destroy }.not_to raise_error
        expect(Sensemaker::Job.find_by(id: job.id)).to be(nil)
      end
    end
  end
end
