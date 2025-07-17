class Budget
  class Question < ApplicationRecord
    translates :text, :hint, touch: true
    include Globalizable

    belongs_to :budget, touch: true
    has_many :answers, class_name: "Investment::Answer"

    validates_translation :text, presence: true

    scope :enabled, -> { where(enabled: true) }

    def title
      text
    end

    private
  end
end
