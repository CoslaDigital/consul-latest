load Rails.root.join("app", "controllers", "verification_controller.rb")

class VerificationController < ApplicationController
  before_action :authenticate_user!
  before_action :verify_lock
  skip_authorization_check

  def show
    step = next_pending_step
    redirect_to step[:path], notice: step[:notice]
  end

  private

    def next_pending_step
      return { path: account_path } if current_user.organization?

      # 1. Evaluate pipeline requirements
      required_steps = build_pipeline_for(current_user)

      # 2. Find the first step the user hasn't completed
      pending_step = required_steps.find { |step| !step_completed?(step) }

      # 3. Route or promote
      if pending_step
        route_for_step(pending_step)
      else
        promote_to_fully_verified!(current_user)
        { path: account_path, notice: t("verification.redirect_notices.already_verified") }
      end
    end

    def build_pipeline_for(user)
      steps = []

      # YS User Pipeline
      if User.valid_ys_document?(user.document_number)
        steps << :ys_demographics if Setting["verification.ys_requires_demographics"]
        return steps
      end

      # Standard User Pipeline (Controlled via Admin Settings)
      steps << :residence if Setting["verification.require_residence"]
      steps << :sms if Setting["verification.require_sms"]
      steps << :letter if Setting["verification.require_letter"]

      steps
    end

    def step_completed?(step)
      case step
        # Check the timestamp instead of the raw demographic data
      when :ys_demographics then current_user.verified_at.present?
      when :residence then current_user.residence_verified?
      when :sms then current_user.level_two_verified?
      when :letter then current_user.level_three_verified?
      else true
      end
    end

    def route_for_step(step)
      case step
      when :ys_demographics
        { path: new_verification_ys_demographic_path }
      when :residence
        { path: new_residence_path }
      when :sms
        current_user.verification_sms_sent? ? { path: edit_sms_path } : { path: verified_user_path }
      when :letter
        current_user.verification_letter_sent? ? { path: edit_letter_path } : { path: new_letter_path }
      end
    end

    def promote_to_fully_verified!(user)
      updates = {}
      updates[:residence_verified_at] = Time.current unless user.residence_verified?
      updates[:level_two_verified_at] = Time.current unless user.level_two_verified?

      user.update_columns(updates) if updates.any?
    end
end
