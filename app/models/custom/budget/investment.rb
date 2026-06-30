load Rails.root.join("app", "models", "budget", "investment.rb")

class Budget
  class Investment < ApplicationRecord
    has_many :answers, class_name: "Investment::Answer"
    accepts_nested_attributes_for :answers

    validates_translation :description, presence: false,
                                        length: { maximum: Budget::Investment.description_max_length }

    validate :all_answers

    def all_answers
      errors.add(:answers, :missing_mandatory) unless has_all_answers?
    end

    def has_all_answers?
  # 1. Get the IDs of all mandatory and enabled questions for this budget.
  # This remains an efficient database query.
      mandatory_question_ids = budget.questions
                                     .where(is_mandatory: true, enabled: true)
                                     .pluck(:id)

  # 2. Count the answers currently in memory that are for a mandatory question
  #    and have non-blank text. This avoids querying the database for unsaved records.
      answered_mandatory_count = answers.count do |answer|
        # Skip answers that are blank or marked for deletion
        next if answer.marked_for_destruction? || answer.text.blank?

        # Check if the answer's question_id is in our mandatory list
        mandatory_question_ids.include?(answer.budget_question_id)
      end
  result = (answered_mandatory_count == mandatory_question_ids.count)

  # 3. The validation passes if the counts are equal.
      result
    end
  end
end
