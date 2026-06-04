load Rails.root.join("app", "models", "budget.rb")

class Budget < ApplicationRecord
  include Documentable
  has_many :questions, class_name: "Budget::Question"

  enum kind: { budget: "budget", election: "election" }

  before_save :enforce_election_settings, if: :election?

  private

    def enforce_election_settings
      self.hide_money = true
    end

end
