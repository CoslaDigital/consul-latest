FactoryBot.define do
  factory :sensemaker_job, class: "Sensemaker::Job" do
    user
    script { "categorize" }
    started_at { Time.current }
    finished_at { nil }
    error { nil }
    analysable_type { "Debate" }
    analysable_id { create(:debate).id }
    additional_context { "Test context" }
    published { false }

    trait :unpublished do
      published { false }
    end

    trait :published do
      script { "report_ui" }
      published { true }
    end

    trait :health_check do
      script { "health_check" }
    end

    trait :categorize do
      script { "categorize" }
    end

    trait :bridge_scores do
      script { "bridge_scores" }
    end

    trait :report_text do
      script { "report_text" }
    end

    trait :report_ui do
      script { "report_ui" }
    end

    trait :propositions do
      script { "propositions" }
    end

    trait :refine_propositions do
      script { "refine_propositions" }
    end

    trait :ranked_propositions do
      script { "ranked_propositions" }
    end

    trait :publishable do
      script { "report_ui" }
      finished_at { Time.current }
      error { nil }
    end
  end
end
