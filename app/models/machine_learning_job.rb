class MachineLearningJob < ApplicationRecord
  belongs_to :user, optional: false

  # FIX: A job is only "started" if it hasn't finished or errored yet.
  # This prevents the "Cancel" button from showing up on finished jobs.
  def started?
    started_at.present? && finished_at.blank? && error.blank?
  end

  def finished?
    finished_at.present? && error.blank?
  end

  def errored?
    error.present?
  end

  # NEW: Helper for the UI
  def dry_run?
    # This assumes you added the boolean column 'dry_run' to the DB
    # or added 'attr_accessor :dry_run' as a stop-gap.
    respond_to?(:dry_run) && !!dry_run
  end

  def running_for_too_long?
    started? && started_at < 1.day.ago
  end
end
