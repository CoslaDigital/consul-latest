load Rails.root.join("app", "controllers", "verification_controller.rb")

class VerificationController < ApplicationController
  before_action :authenticate_user!
  before_action :verify_lock
  skip_authorization_check

  def show
    return redirect_to(account_path) if current_user.organization?

    pending_step = current_user.pending_verification_steps.first

    if pending_step
      step_route = route_for_step(pending_step)
      redirect_to step_route[:path], notice: step_route[:notice]
    else
      # Stamp the DB so queries for verified users find them
      current_user.promote_to_fully_verified!
      redirect_to account_path, notice: t("verification.redirect_notices.already_verified")
    end
  end

  private

    def route_for_step(step)
      case step
      when :ys_demographics
        { path: new_ys_demographic_path }
      when :residence
        { path: new_residence_path }
      when :sms
        current_user.verification_sms_sent? ? { path: edit_sms_path } : { path: verified_user_path }
      when :letter
        current_user.verification_letter_sent? ? { path: edit_letter_path } : { path: new_letter_path }
      end
    end
end
