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

        # 2. Clear Devise's stored location so it doesn't hijack our route
        session["user_return_to"] = nil

        # 3. Route the user based on our protected method below
        redirect_to after_sign_in_path_for(user)
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

  protected

  def after_sign_in_path_for(resource)
    # If the user is NOT unverified (i.e., they ARE verified)
    return my_area_path unless resource.unverified?

    # If the user IS unverified, go to verification
    verification_path
  end
end
