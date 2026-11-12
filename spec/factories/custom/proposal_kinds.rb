FactoryBot.define do
  factory :proposal_kind do
    sequence(:name) { |n| "Project Type #{n}" }
    sequence(:slug) { |n| "project-type-#{n}" }
  end
end
