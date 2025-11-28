class Event < ApplicationRecord
  include CalendarItem
  include Imageable
  validates :name, :starts_at, presence: true

  # These format the DB data so it looks right in the inputs
  def start_date
    starts_at&.strftime("%d/%m/%Y")
  end

  def start_time
    starts_at&.strftime("%H:%M")
  end

  def end_date
    ends_at&.strftime("%d/%m/%Y")
  end

  def end_time
    ends_at&.strftime("%H:%M")
  end

  # --- SETTERS (From the Form) ---
  # These take the form data and combine them into the DB column
  def start_date=(date_str)
    @start_date_str = date_str
    assign_starts_at
  end

  def start_time=(time_str)
    @start_time_str = time_str
    assign_starts_at
  end

  def end_date=(date_str)
    @end_date_str = date_str
    assign_ends_at
  end

  def end_time=(time_str)
    @end_time_str = time_str
    assign_ends_at
  end

  private

  def assign_starts_at
    return if @start_date_str.blank?

    # Parse the UK Date format specific to your JS settings
    date = Date.strptime(@start_date_str, "%d/%m/%Y") rescue nil

    if date
      time = @start_time_str.presence || "00:00"
      # Combine Date and Time
      self.starts_at = Time.zone.parse("#{date} #{time}")
    end
  end

  def assign_ends_at
    return if @end_date_str.blank?

    date = Date.strptime(@end_date_str, "%d/%m/%Y") rescue nil

    if date
      time = @end_time_str.presence || "23:59"
      self.ends_at = Time.zone.parse("#{date} #{time}")
    end
  end

  def self.all_in_range(start_date, end_date)
    # 1. Fetch Manual Events (This model)
    events = self.where(starts_at: start_date..end_date)

    budgets = Budget.published.includes(:phases).select do |b|
      b.calendar_start.present? && (start_date..end_date).cover?(b.calendar_start)
    end
    budget_phases = Budget::Phase.joins(:budget)
                                .merge(Budget.published)
                                .where(enabled: true)
                                .where(starts_at: start_date..end_date)
    processes = Legislation::Process.open.where(start_date: start_date..end_date)

    polls = defined?(Poll) ? Poll.where(starts_at: start_date..end_date) : []

    (events + budgets + budget_phases + processes + polls).sort_by(&:calendar_start)
  end
  def kind
    "generic_event"
  end
end
