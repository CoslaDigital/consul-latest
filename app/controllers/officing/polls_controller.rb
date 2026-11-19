class Officing::PollsController < Officing::BaseController
  before_action :verify_booth

  def index
    @polls = current_user.poll_officer? ? current_user.poll_officer.voting_days_assigned_polls : []
    @polls = @polls.select { |poll| poll.current?(Time.current) || poll.current?(1.day.ago) }
  end

  def final
    @polls = if current_user.poll_officer?
               current_user.poll_officer.final_days_assigned_polls.select do |poll|
                 if poll.budget_poll?
                   !poll.budget.finished? && (poll.expired? || poll.ends_at.today?)
                 else
                   poll.ends_at > Poll::RECOUNT_DURATION.ago && poll.expired? || poll.ends_at.today?
                 end
               end
             else
               []
             end
  end
end
