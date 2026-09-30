load Rails.root.join("app", "models", "budget", "ballot", "line.rb")

class Budget
  class Ballot
    class Line < ApplicationRecord
      acts_as_list scope: [:ballot_id, :group_id]

      before_validation :set_denormalized_ids
    end
  end
end
