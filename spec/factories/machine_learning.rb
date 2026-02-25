FactoryBot.define do
  factory :machine_learning_job do
    script { "proposal_tags" }
    user
    started_at { Time.current }
    dry_run { false }
    config { {} }
  end

  factory :ml_summary_comment do
    commentable factory: :proposal
    body { "Sample summary" }
  end
end
