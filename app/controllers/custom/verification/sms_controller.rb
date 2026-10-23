load Rails.root.join("app", "controllers", "verification", "sms_controller.rb")

class Verification::SmsController < ApplicationController
  # 1. Strip out Consul's hardcoded Census requirement
  skip_before_action :verify_resident!, raise: false

  # 2. Inject our dynamic pipeline security check instead
  before_action :verify_pipeline_allows_sms!, only: [:new, :create, :edit, :update]

  private

    # OVERRIDE: Let the central verification engine decide the next step.
    # Instead of hardcoding a redirect to the letter path, we send them back
    # to `/verification` so the engine can instantly promote them to fully
    # verified if the Letter step is disabled.
    def redirect_to_next_path
      current_user.reload

      redirect_to verification_path, notice: t("verification.sms.update.flash.level_two.success")
    end

    # NEW: Security check that respects the dynamic pipeline.
    # This ensures a user cannot force their way to `/sms/new` by typing the URL
    # if they haven't finished the demographics/census form first.
    def verify_pipeline_allows_sms!
      unless current_user.pending_verification_steps.first == :sms
        redirect_to verification_path
      end
    end
end
