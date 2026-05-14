module OfficersHelper
  def no_shifts?
    current_user.poll_officer.officer_assignments.where(date: Time.current.to_date).blank?
  end

  def status_label_class(status)
    case status
    when "available" then "success"
    when "in_discussion" then "warning"
    when "finished" then "secondary"
    else ""
    end
  end
end
