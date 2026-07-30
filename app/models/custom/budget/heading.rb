load Rails.root.join("app","models","budget","heading.rb")
class Budget
  class Heading < ApplicationRecord

    include Documentable

    # Returns this heading's specific winner count if set.
    # Otherwise, it falls back to the parent budget's default.
    def effective_max_winners
      max_winners.presence || budget.stv_winners
    end

  end
end
