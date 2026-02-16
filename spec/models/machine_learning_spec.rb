require "rails_helper"

describe MachineLearning do
  let(:user) { create(:administrator).user }
  let(:job) { create(:machine_learning_job, user: user) }
  let(:ml) { MachineLearning.new(job) }

  before do
    allow(Setting).to receive(:[]).and_call_original
    allow(Setting).to receive(:[]).with("feature.machine_learning").and_return(true)
    allow(Setting).to receive(:[]).with("llm.provider").and_return("openai")
    allow(Setting).to receive(:[]).with("llm.model").and_return("gpt-4")

    ml.instance_variable_set(:@total_tokens_used, 0)

    # Global override: ensure test records aren't skipped by freshness logic
    allow_any_instance_of(MachineLearning).to receive(:should_reprocess_record?).and_return(true)
  end

  describe "Initialization" do
    it "correctly sets flags from the job record" do
      job.update!(dry_run: true)
      ml_new = MachineLearning.new(job)
      expect(ml_new.dry_run).to be true
    end
  end

  describe "Freshness Logic (#should_reprocess_record?)" do
    let(:proposal) { create(:proposal) }

    before do
      proposal.update!(summary_en: "Valid summary for testing")
      allow_any_instance_of(MachineLearning).to receive(:should_reprocess_record?).and_call_original
    end

    it "returns false if the record has already been processed and is not stale" do
      create(:tagging, taggable: proposal, context: "ml_tags")
      create(:machine_learning_info, kind: "tags", generated_at: 1.day.from_now)

      expect(ml.send(:should_reprocess_record?, proposal, "tags")).to be false
    end

    it "returns true if the record was updated after the last global run" do
      create(:tagging, taggable: proposal, context: "ml_tags")
      create(:machine_learning_info, kind: "tags", generated_at: 1.day.ago)
      proposal.update!(updated_at: Time.current)

      expect(ml.send(:should_reprocess_record?, proposal, "tags")).to be true
    end
  end

  describe "Tag Generation" do
    it "creates new tags and taggings for a proposal" do
      proposal = create(:proposal)
      proposal.update!(title_en: "Clean Water", description_en: "Filter", summary_en: "Summary")

      allow(MlHelper).to receive(:generate_tags).and_return({
                                                              "tags" => ["Environment", "Parks"],
                                                              "usage" => { "total_tokens" => 100 }
                                                            })

      ml.send(:process_tags_for,
              scope: [[proposal.id, proposal.title, proposal.description]],
              type: 'Proposal',
              log_name: "proposal tags")

      tag_names = Tagging.where(taggable: proposal, context: 'ml_tags').joins(:tag).pluck('tags.name')
      expect(tag_names.map(&:downcase)).to include("environment", "parks")
    end
  end

  describe "Core Processing Tasks" do
    it "generates and saves summary comments with sentiment" do
      proposal = create(:proposal)
      proposal.update!(summary_en: "Required Summary")
      create(:comment, commentable: proposal, body: "Supportive comment.")

      allow(MlHelper).to receive(:summarize_comments).and_return({
                                                                   "summary_markdown" => "Users are supportive.",
                                                                   "sentiment" => { "positive" => 90, "negative" => 5, "neutral" => 5 },
                                                                   "usage" => { "total_tokens" => 100 }
                                                                 })

      expect {
        ml.generate_proposal_comments_summary
      }.to change(MlSummaryComment, :count).by(1)
    end

    it "identifies and creates related content records" do
      # 1. Create two proposals with explicit English translations
      p1 = create(:proposal)
      p1.update!(title_en: "Main Proposal", summary_en: "Summary 1")

      p2 = create(:proposal)
      p2.update!(title_en: "Similar Proposal", summary_en: "Summary 2")

      RelatedContent.delete_all

      # 2. Mock should_reprocess_record? to ONLY process p1
      # This ensures we don't try to create duplicate relationships
      allow(ml).to receive(:should_reprocess_record?).and_wrap_original do |original_method, record, kind|
        if record == p1
          true # Only process p1
        else
          false # Skip p2
        end
      end

      # 3. Mock the LLM to find p2 as similar to p1
      allow(MlHelper).to receive(:find_similar_content).and_return({
                                                                     "indices" => [0], # After filtering out p1, p2 will be at index 0
                                                                     "usage" => { "total_tokens" => 30 }
                                                                   })

      # 4. Expect the count to increase by 2 because:
      #    - The method creates one relationship (p1 -> p2)
      #    - The after_create callback creates the opposite (p2 -> p1)
      expect {
        ml.send(:process_related_content_for, Proposal, "filename.json")
      }.to change(RelatedContent, :count).by(2)

      # 5. Verify both relationships exist
      expect(RelatedContent.where(parent_relationable: p1, child_relationable: p2)).to exist
      expect(RelatedContent.where(parent_relationable: p2, child_relationable: p1)).to exist
    end
  end

  describe "Sentiment Analysis Math" do
    it "correctly rounds and balances sentiment to exactly 100%" do
      raw_data = { "positive" => 6, "negative" => 2, "neutral" => 5 }
      result = ml.send(:process_sentiment_data, raw_data)
      expect(result["positive"] + result["negative"] + result["neutral"]).to eq(100)
    end
  end

  describe "Cleanup Methods" do
    it "removes existing summaries for the correct type" do
      p = create(:proposal)
      p.update!(summary_en: "S")
      create(:ml_summary_comment, commentable: p)

      ml.send(:cleanup_comments_summary_for!, "Proposal")
      expect(MlSummaryComment.where(commentable_type: "Proposal").count).to eq 0
    end
  end

  describe "Error Handling" do
    it "captures and logs errors to the job record" do
      allow(ml).to receive(:generate_proposal_comments_summary).and_raise(StandardError.new("API Error"))
      job.update!(script: "proposal_comments")
      ml.run
      expect(job.reload.error).to include("API Error")
    end
  end
end
