class Budgets::Investments::MyBallotComponent < ApplicationComponent; end

load Rails.root.join("app", "components", "budgets", "investments", "my_ballot_component.rb")

class Budgets::Investments::MyBallotComponent < ApplicationComponent
  attr_reader :ballot, :heading, :investment_ids, :assigned_heading
  use_helpers :can?, :heading_link, :custom_t

  def initialize(ballot:, heading:, investment_ids:, assigned_heading: nil)
    @ballot = ballot
    @heading = heading
    @investment_ids = investment_ids
    @assigned_heading = assigned_heading
  end

  def render?
    heading && can?(:show, ballot)
  end

  private

    def budget
      ballot.budget
    end

    def investments
#      ballot.investments.by_heading(heading.id).sort_by_ballot_lines
       ballot.investments
            .where(budget_ballot_lines: { heading_id: heading.id })
            .order("budget_ballot_lines.position ASC")
 
    end
    
    def voting_style_name
      ballot.voting_style.name
    end

    def voted_info_amount_spent
      price = investments.sum(:price).to_i
      budget.formatted_amount(price)
    end
end
