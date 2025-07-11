load Rails.root.join('app', 'models', 'budget', 'investment.rb')

class Budget
  class Investment < ApplicationRecord

    has_many :answers, class_name: "Investment::Answer"
    accepts_nested_attributes_for :answers

    validates_translation :description, presence: false, length: { maximum: Budget::Investment.description_max_length }

    validate :all_answers

    def all_answers
      errors.add(:answers, :missing_mandatory) unless has_all_answers?
    end
    
    def has_all_answers?
  # 1. Get the count of all mandatory questions for this budget.
  # This is one efficient database query.
  mandatory_question_count = budget.questions.where(is_mandatory: true).count

  # 2. Count how many of this investment's answers are for mandatory questions
  #    and have non-blank text. This is a second efficient query using a JOIN.
  answered_mandatory_count = answers
                               .joins(:budget_question)
                               .where(budget_questions: { is_mandatory: true, enabled: true })
                               .where.not(text: [nil, ""])
                               .count

  # 3. The validation passes if the counts are equal.
  answered_mandatory_count == mandatory_question_count
end

  end
end