class YsLoginController < Devise::SessionsController
  before_action :ensure_card_login_enabled!

  def new
  end

  def create
    username = params.dig(:user, :username)
    email = params.dig(:user, :email) # Capture the email from the dual-field form

    if User.validate_document_number(username)
      # Pass BOTH parameters to our newly merged model method
      user = User.log_in_or_create_ys_user(username, email)

      if user&.persisted?
        # CRITICAL: Devise checks if they have clicked the email confirmation link yet
        if user.active_for_authentication?
          set_flash_message!(:notice, :signed_in)
          sign_in(user, event: :authentication)
          session["user_return_to"] = nil
          redirect_to after_sign_in_path_for(user)
        else
          # User was just created and Devise dispatched the email. Deny immediate login.
          flash[:notice] = "A message with a confirmation link has been sent to your email address. Please follow the link to activate your account."
          redirect_to root_path
        end
      else
        error_message = user&.errors&.full_messages&.join(', ') || "Please try again."
        flash[:alert] = "Could not sign you in. #{error_message}"
        render :new, status: :unprocessable_entity
      end
    else
      # Uses the granular error message for bad card formats
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
