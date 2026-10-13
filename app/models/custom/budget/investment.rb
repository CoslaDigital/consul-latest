load Rails.root.join("app", "models", "budget", "investment.rb")

class Budget
  class Investment < ApplicationRecord
    has_many :lines, class_name: "Budget::Ballot::Line", foreign_key: "investment_id",
             dependent: :destroy, inverse_of: :investment

    has_many :answers, class_name: "Investment::Answer"
    scope :sort_by_votes, -> { order(votes: :desc) }
    accepts_nested_attributes_for :answers

    validates_translation :description, presence: false,
                          length: { maximum: Budget::Investment.description_max_length }

    validate :all_answers

    # 1. ADD THIS CALLBACK
    before_validation :normalize_youtube_shorts_url

    def all_answers
      errors.add(:answers, :missing_mandatory) unless has_all_answers?
    end

    def has_all_answers?
      mandatory_question_ids = budget.questions
                                     .where(is_mandatory: true, enabled: true)
                                     .pluck(:id)

      answered_mandatory_count = answers.count do |answer|
        next if answer.marked_for_destruction? || answer.text.blank?
        mandatory_question_ids.include?(answer.budget_question_id)
      end

      result = (answered_mandatory_count == mandatory_question_ids.count)

      result
    end

    private

      # 2. ADD THIS METHOD
      def normalize_youtube_shorts_url
        return unless video_url.present?

        # If it's a YouTube short, extract the ID and convert it to a standard watch URL
        if video_url.include?("youtube.com/shorts/")
          # Example: https://youtube.com/shorts/K20_AXNLbfU?si=IBU... -> K20_AXNLbfU
          video_id = video_url.split("/shorts/").last.split("?").first
          self.video_url = "https://www.youtube.com/watch?v=#{video_id}"
        end
      end
  end
end
