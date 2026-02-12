class Admin::MachineLearningController < Admin::BaseController
  before_action :load_machine_learning_job, only: [:show, :execute]

  def show
  end

  def execute
    # 1. Update the job metadata
    # Also capture the 'mode' parameter for Dry Run support
    is_dry_run = params[:mode] == "dry_run"

    @machine_learning_job.update!(
      script: params[:script],
      user: current_user,
      started_at: Time.current,
      finished_at: nil,
      error: nil,
      dry_run: is_dry_run # Ensure you have this column or attribute
    )

    # 2. RUN IN FOREGROUND (Blocking call)
    # We call .run directly. The browser will wait until it's done.
    ::MachineLearning.new(@machine_learning_job, dry_run: is_dry_run).run

    redirect_to admin_machine_learning_path,
                notice: "Foreground execution complete."
  end

  def cancel
    Delayed::Job.where(queue: "machine_learning").destroy_all
    MachineLearningJob.destroy_all

    redirect_to admin_machine_learning_path,
                notice: t("admin.machine_learning.notice.delete_generated_content")
  end

  private

    def load_machine_learning_job
      @machine_learning_job = MachineLearningJob.first_or_initialize
    end
end
