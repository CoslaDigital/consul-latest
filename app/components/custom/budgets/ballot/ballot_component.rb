class Budgets::Ballot::BallotComponent < ApplicationComponent; end

load Rails.root.join("app","components","budgets","ballot", "ballot_component.rb")

class Budgets::Ballot::BallotComponent < ApplicationComponent
  attr_reader :ballot
  use_helpers :custom_t
  
  def initialize(ballot)
    @ballot = ballot
  end

  def budget
    ballot.budget
  end

  private

    def ballot_groups
      ballot.groups.sort_by_name
    end

    def no_balloted_groups
      budget.groups.sort_by_name - ballot.groups
    end

    def group_path(group)
      if group.multiple_headings?
        budget_group_path(budget, group)
      else
        budget_investments_path(budget, heading_id: group.headings.first)
      end
    end

    def group_investments(group)
#      ballot.investments.by_group(group.id).sort_by_ballot_lines
       @ballot.investments
         .where(budget_ballot_lines: { group_id: group.id })
         .order('budget_ballot_lines.position ASC')
    end
end
