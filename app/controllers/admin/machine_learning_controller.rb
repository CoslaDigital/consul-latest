class Admin::MachineLearningController < Admin::BaseController
  before_action :load_machine_learning_job, only: [:show, :execute]

  def show
  end

  def execute
    # 1. Standardize parameters (Handling both 'execution_mode' and 'dry_run' params)
    script = params[:script]
    is_dry_run = params[:execution_mode] == "dry_run" || params[:dry_run] == "true"

    # 2. Create a FRESH job record
    # This allows the UI to show a history of runs
    @job = MachineLearningJob.create!(
      script: script,
      user: current_user,
      started_at: Time.current,
      dry_run: is_dry_run
    )

    # 3. Execution
    # If your background worker (DelayedJob/Sidekiq) isn't running,
    # use MachineLearning.new(@job).run (without .delay) for instant feedback.
    ::MachineLearning.new(@job).delay(queue: 'machine_learning').run

    notice_msg = is_dry_run ? "Dry run started (Background)" : "Job started in background."
    redirect_to admin_machine_learning_path, notice: notice_msg
  end

  def cancel
    # Since you are running in the foreground, this will only
    # clear the state for the next page load.
    MachineLearningJob.delete_all

    redirect_to admin_machine_learning_path,
                notice: t("admin.machine_learning.notice.delete_generated_content")
  end

  private

  def load_machine_learning_job
    # Ensures we always work with the same single job record
    @machine_learning_job = MachineLearningJob.first_or_initialize
  end
end
