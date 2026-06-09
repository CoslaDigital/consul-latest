class YsLoginController < Devise::SessionsController
  # This action just shows the form
  def new
  end

  # This action handles the form submission
  def create
    username = params.dig(:user, :username)

    # This code follows your validation logic for a 16-digit number.
    if User.validate_document_number(username)
      user = User.log_in_or_create_ys_user(username)

      if user&.persisted?
        set_flash_message!(:notice, :signed_in)

        # 1. Sign the user in without automatically redirecting
        sign_in(user, event: :authentication)

        # 2. Check verification status and redirect accordingly
        if user.unverified?
          # This hits your VerificationController#show, which handles routing
          # them to the exact step they need via your next_step_path logic.
          redirect_to verification_path
        else
          # Fallback to standard Devise redirect if they are already verified
          redirect_to after_sign_in_path_for(user)
        end
      else
        error_message = user&.errors&.full_messages&.join(', ') || "Please try again."
        flash[:alert] = "Could not sign you in. #{error_message}"
        render :new, status: :unprocessable_entity
      end
    else
      flash[:alert] = "The number you entered is not valid. Please enter a valid 16-digit number."
      render :new, status: :unprocessable_entity
    end
  end
end
