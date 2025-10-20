class YsLoginController < Devise::SessionsController
  # This action just shows the form
  def new
  end

  # This action handles the form submission
  def create
    username = params.dig(:user, :username)

    # Note: Your description says 14 digits, but your validation code checks for 16.
    # This code follows your validation logic for a 16-digit number.
    if User.validate_document_number(username)
      user = User.log_in_or_create_ys_user(username)

      if user&.persisted?
        set_flash_message!(:notice, :signed_in)
        sign_in_and_redirect user, event: :authentication
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