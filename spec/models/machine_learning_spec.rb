require "rails_helper"

RSpec.describe MachineLearning, type: :model do
  let(:admin) { create(:administrator).user }
  let(:job) { create(:machine_learning_job, user: admin) }
  let(:ml_service) { MachineLearning.new(job) }
  # Move this here so it is available to ALL tests in this file
  let!(:proposal) { create(:proposal, title: "Clean the park", description: "It is dirty") }

  describe "#run" do
    context "when script is unknown" do
      it "raises an error and updates job" do
        job.update!(script: "invalid_script")

        expect { ml_service.run }.to raise_error(RuntimeError, /Unknown script/)
        expect(job.reload.error).to match(/Unknown script/)
      end
    end

    context "when a script fails" do
      it "records the error and re-raises" do
        job.update!(script: "proposal_tags")

        allow(MlHelper).to receive(:generate_tags).and_raise(StandardError, "API Timeout")

        expect { ml_service.run }.to raise_error(StandardError, "API Timeout")
        expect(job.reload.error).to eq("API Timeout")
      end
    end
  end

  describe "Core Processing Tasks" do
    before do
      FileUtils.rm_rf(MachineLearning.data_folder)
    end

    describe "Tagging" do
      it "generates and saves tags for proposals" do
        job.update!(script: "proposal_tags")
        allow(MlHelper).to receive(:generate_tags).and_return(
          {
            "tags" => ["Environment", "Parks"],
            "usage" => { "total_tokens" => 50 }
          }
        )

        ml_service.run

        expect(job.reload.records_processed).to eq(1)
        expect(job.total_tokens).to eq(50)

        tag_names = Tagging.where(taggable: proposal, context: "ml_tags")
                           .joins(:tag).pluck("tags.name")
        expect(tag_names).to contain_exactly("Environment", "Parks")
      end
    end

    describe "Comments Summary" do
      it "generates summaries and sentiment for proposals" do
        create(:comment, commentable: proposal, body: "Great idea!")
        job.update!(script: "proposal_summary_comments")

        sentiment = { "positive" => 100, "negative" => 0, "neutral" => 0 }
        allow(MlHelper).to receive(:summarize_comments).and_return(
          {
            "summary_markdown" => "Users are supportive.",
            "sentiment" => sentiment,
            "usage" => { "total_tokens" => 100 }
          }
        )

        ml_service.run

        summary = MlSummaryComment.find_by(commentable: proposal)
        expect(summary.body).to eq("Users are supportive.")
        expect(summary.sentiment_analysis).to eq(sentiment)
      end
    end

    describe "Related Content" do
      it "identifies similar proposals" do
        p1 = proposal
        p2 = create(:proposal, title: "Construct a swimming area")
        job.update!(script: "proposal_related_content")

        allow(MlHelper).to receive(:find_similar_content).and_return(
          {
            "indices" => [0],
            "usage" => { "total_tokens" => 200 }
          }
        )

        ml_service.run

        related = RelatedContent.where(parent_relationable: p1, child_relationable: p2)
        expect(related.exists?).to be true
      end
    end
  end

  describe "Data Integrity" do
    it "clears existing data when force_update is enabled" do
      # Use the proposal available in this scope
      proposal.set_tag_list_on(:ml_tags, ["OldTag"])
      proposal.save!

      job.update!(script: "proposal_tags", config: { force_update: "1" })

      allow(MlHelper).to receive(:generate_tags).and_return(
        {
          "tags" => ["NewTag"],
          "usage" => { "total_tokens" => 10 }
        }
      )

      ml_service.run
      expect(Tagging.where(context: "ml_tags").count).to eq(1)
      expect(Tagging.joins(:tag).pluck("tags.name")).to include("NewTag")
      expect(Tagging.joins(:tag).pluck("tags.name")).not_to include("OldTag")
    end

    it "does not reprocess fresh records unless forced" do
      # Now 'proposal' is recognized here
      proposal.set_tag_list_on(:ml_tags, ["Environment"])
      proposal.save!

      job.update!(script: "proposal_tags", config: { force_update: "0" })

      expect(MlHelper).not_to receive(:generate_tags)
      ml_service.run
    end
  end
end
