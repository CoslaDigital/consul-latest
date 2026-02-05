class Admin::MachineLearningController < Admin::BaseController
  before_action :load_machine_learning_job, only: [:show, :execute]

  def show
  end

  def execute
    # 1. Capture parameters
    script = params[:script]
    is_dry_run = params[:execution_mode] == "dry_run"

    # We reset finished_at and error so the UI state transitions back to "working"
    @machine_learning_job.update!(
      script: script,
      user: current_user,
      started_at: Time.current,
      finished_at: nil,
      error: nil,
      dry_run: is_dry_run
    )

    #Execution
    #::MachineLearning.new(@machine_learning_job).run
    ::MachineLearning.new(@machine_learning_job).delay(queue: 'machine_learning').run

    notice_msg = is_dry_run ? "Dry run complete: analyzed data but made no changes." : "Script executed successfully."
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
