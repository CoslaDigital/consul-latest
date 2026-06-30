module OffersHelper
  def status_color_for(status)
    case status
    when "accepted" then "#43ac6a" # Green
    when "confirmed" then "#2196f3" # Blue
    when "rejected" then "#f04124" # Red
    when "fulfilled" then "#777777" # Grey
    else "#e6e6e6"
    end
  end

  def status_label_class(status)
    case status
    when "accepted" then "success"
    when "confirmed" then "info"
    when "rejected" then "alert"
    when "fulfilled" then "secondary"
    else ""
    end
  end
end
