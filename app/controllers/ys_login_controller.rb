class YsLoginController < Devise::SessionsController
  before_action :ensure_card_login_enabled!

  def new
  end

  def create
    username = params.dig(:user, :username)
    email = params.dig(:user, :email)

    if User.validate_document_number(username)
      # Check if this legacy user's email already belongs to someone else
      if email.present? && User.exists?(email: email) && !User.exists?(username: username, email: email)
        flash[:alert] = "The email address #{email} is already registered to another account."
        render :new, status: :unprocessable_entity
        return
      end

      user = User.log_in_or_create_ys_user(username, email)

      if user&.persisted? && user.errors.empty?

        # 1. Catch unconfirmed users BEFORE trying to log them in
        if Setting["verification.require_email_confirmation"].present? && user.confirmed_at.blank?

          # Grab the new email from the parking lot if they are a legacy user, otherwise use their main email
          target_email = user.unconfirmed_email.presence || user.email

          flash[:notice] = "Account created successfully! Please check your inbox (#{target_email}) to click the confirmation link before you can fully participate."
          redirect_to new_ys_login_path
          return # Stop execution so we don't accidentally sign them in
        end

        # 2. HAPPY PATH: User is confirmed, log them in and route them to the app
        sign_in(user, event: :authentication)
        session["user_return_to"] = nil
        set_flash_message!(:notice, :signed_in)

        redirect_to after_sign_in_path_for(user)
      else
        error_message = user&.errors&.full_messages&.join(', ') || "Please try again."
        flash[:alert] = "Could not sign you in. #{error_message}"
        render :new, status: :unprocessable_entity
      end
    else
      flash[:alert] = User.ys_document_error_message(username)
      render :new, status: :unprocessable_entity
    end
  end

  protected

  def after_sign_in_path_for(resource)
    # Route them to the verification pipeline if they haven't finished all required steps
    if resource.unverified? || !resource.pipeline_complete?
      # Store the final destination so the pipeline knows where to
      # send them after they successfully finish the demographic/SMS steps
      target_path = Setting.my_area_enabled? ? my_area_path : super
      session["user_return_to"] = target_path

      return verification_path
    end

    if Setting.my_area_enabled?
      my_area_path
    else
      super
    end
  end

  def ensure_card_login_enabled!
    unless Setting.enable_card_login?
      redirect_to new_user_session_path, alert: "NEC/Young Scot card login is currently disabled."
    end
  end
end
