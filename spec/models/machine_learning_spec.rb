require "rails_helper"

RSpec.describe MachineLearning do
  let(:admin) { create(:administrator).user }
  let(:job) { create(:machine_learning_job, user: admin) }
  let(:ml_service) { MachineLearning.new(job) }
  let!(:proposal) { create(:proposal, title: "Clean the park", description: "It is dirty") }

  before do
    allow(Setting).to receive(:[]).and_call_original
    allow(Setting).to receive(:[]).with("feature.machine_learning").and_return(true)
    allow(Setting).to receive(:[]).with("llm.provider").and_return("openai")
    allow(Setting).to receive(:[]).with("llm.model").and_return("gpt-4")
    ml_service.instance_variable_set(:@total_tokens_used, 0)
    allow_any_instance_of(MachineLearning).to receive(:should_reprocess_record?).and_return(true)
  end

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

  describe "Freshness Logic (#should_reprocess_record?)" do
    before do
      proposal.update!(summary_en: "Valid summary for testing")
      allow_any_instance_of(MachineLearning).to receive(:should_reprocess_record?).and_call_original
    end

    it "returns false if the record has already been processed and is not stale" do
      create(:tagging, taggable: proposal, context: "ml_tags")
      MachineLearningInfo.create!(kind: "tags", generated_at: 1.day.from_now)

      expect(ml_service.send(:should_reprocess_record?, proposal, "tags")).to be false
    end

    it "returns true when the record has no ml_tags yet (not processed)" do
      expect(proposal.taggings.where(context: "ml_tags")).to be_empty
      expect(ml_service.send(:should_reprocess_record?, proposal, "tags")).to be true
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

      it "generates and saves summary for open-ended poll question answers" do
        poll = create(:poll)
        question = create(:poll_question_open, poll: poll)
        question.update!(title_en: "What would you improve?")

        mock_conversation = instance_double(Ml::Conversation,
                                            comments: [double(body: "More green spaces.")],
                                            compile_context: "Question: What would you improve?")
        allow(Ml::Conversation).to receive(:new).with("Poll::Question",
                                                      question.id).and_return(mock_conversation)
        allow(MlHelper).to receive(:summarize_comments).and_return({
          "summary_markdown" => "Citizens want more green spaces.",
          "sentiment" => { "positive" => 80, "negative" => 10, "neutral" => 10 },
          "usage" => { "total_tokens" => 100 }
        })

        expect do
          ml_service.send(:generate_poll_summary_answers)
        end.to change(MlSummaryComment, :count).by(1)

        summary = MlSummaryComment.find_by(commentable: question)
        expect(summary).to be_present
        expect(summary.body).to include("green spaces")
      end

      it "generates and saves overall summary for a budget" do
        budget = create(:budget)
        budget.update!(name_en: "Participatory Budget 2025")

        mock_conversation = instance_double(Ml::Conversation,
                                            comments: [double(body: "Investment A: Parks renewal."),
                                                       double(body: "Investment B: Library extension.")],
                                            compile_context: "Budget: Participatory Budget 2025")
        allow(Ml::Conversation).to receive(:new).with("Budget", budget.id).and_return(mock_conversation)
        allow(MlHelper).to receive(:summarize_comments).and_return({
          "summary_markdown" => "Key themes: parks and culture.",
          "sentiment" => { "positive" => 70, "negative" => 15, "neutral" => 15 },
          "usage" => { "total_tokens" => 120 }
        })

        expect do
          ml_service.send(:generate_budget_overall_summary)
        end.to change(MlSummaryComment, :count).by(1)

        summary = MlSummaryComment.find_by(commentable: budget)
        expect(summary).to be_present
        expect(summary.body).to include("parks")
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

      it "identifies and creates related content records" do
        p1 = create(:proposal)
        p1.update!(title_en: "Main Proposal", summary_en: "Summary 1")

        p2 = create(:proposal)
        p2.update!(title_en: "Similar Proposal", summary_en: "Summary 2")

        RelatedContent.delete_all

        allow(ml_service).to receive(:should_reprocess_record?)
          .and_wrap_original do |_original_method, record, _kind|
          record == p1
        end
        allow(MlHelper).to receive(:find_similar_content).and_return({
          "indices" => [0],
          "usage" => { "total_tokens" => 30 }
        })

        expect do
          ml_service.send(:process_related_content_for, Proposal.all, "Proposal", "filename.json")
        end.to change(RelatedContent, :count).by(2)

        expect(RelatedContent.where(parent_relationable: p1, child_relationable: p2)).to exist
        expect(RelatedContent.where(parent_relationable: p2, child_relationable: p1)).to exist
      end
    end
  end

  describe "Cleanup Methods" do
    it "removes existing summaries when clear_existing_ml_data comments_summary is used" do
      p = create(:proposal)
      p.update!(summary_en: "S")
      create(:ml_summary_comment, commentable: p)

      ml_service.send(:clear_existing_ml_data, "comments_summary")
      expect(MlSummaryComment.where(commentable_type: "Proposal").count).to eq 0
    end
  end

  describe "Data Integrity" do
    it "clears existing data when force_update is enabled" do
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
      proposal.set_tag_list_on(:ml_tags, ["Environment"])
      proposal.save!

      job.update!(script: "proposal_tags", config: { force_update: "0" })

      # Use real should_reprocess_record? so it returns false for already-tagged proposal
      allow(ml_service).to receive(:should_reprocess_record?).and_call_original
      expect(MlHelper).not_to receive(:generate_tags)
      ml_service.run
    end
  end

  describe "Error Handling" do
    it "captures and logs errors to the job record" do
      allow(ml_service).to receive(:generate_proposal_summary_comments)
        .and_raise(StandardError.new("API Error"))
      job.update!(script: "proposal_summary_comments")

      expect { ml_service.run }.to raise_error(StandardError, "API Error")
      expect(job.reload.error).to include("API Error")
    end
  end
end
