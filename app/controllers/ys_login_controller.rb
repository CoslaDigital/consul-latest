class YsLoginController < Devise::SessionsController
  before_action :ensure_card_login_enabled!

  def new
  end

  def create
    username = params.dig(:user, :username)

    if User.validate_document_number(username)
      user = User.log_in_or_create_ys_user(username)

      if user&.persisted?
        set_flash_message!(:notice, :signed_in)
        sign_in(user, event: :authentication)
        session["user_return_to"] = nil
        redirect_to after_sign_in_path_for(user)
      else
        error_message = user&.errors&.full_messages&.join(', ') || "Please try again."
        flash[:alert] = "Could not sign you in. #{error_message}"
        render :new, status: :unprocessable_entity
      end
    else
      # --- NEW LOGIC: Fetch granular error message ---
      flash[:alert] = User.ys_document_error_message(username)
      render :new, status: :unprocessable_entity
    end
  end

  protected

  def after_sign_in_path_for(resource)
    if resource.unverified?
      # Store the final destination so the verification flow knows where to
      # send them after they successfully enter their email/phone
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
