load Rails.root.join("app", "controllers", "users", "registrations_controller.rb").to_s

class Users::RegistrationsController < Devise::RegistrationsController

  def create
    build_resource(sign_up_params)

    # Custom flag required by Consul
    resource.registering_from_web = true

    # 1. Standard Validations First (Catches missing Terms of Service, blank passwords, etc.)
    if resource.valid?
      # 2. Database Save (Catches soft-deleted DB collisions if valid? passes)
      begin
        resource.save
      rescue ActiveRecord::RecordNotUnique
        resource.errors.add(:email, :taken)
      end
    end

    yield resource if block_given?

    # 3. Success Routing
    if resource.persisted?
      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        respond_with resource, location: after_sign_up_path_for(resource)
      else
        set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        expire_data_after_sign_in!
        respond_with resource, location: after_inactive_sign_up_path_for(resource)
      end

      # 4. Error Routing
    else
      clean_up_passwords resource
      set_minimum_password_length if respond_to?(:set_minimum_password_length)

      # CRITICAL: 422 status forces Turbo to swap the screen and show the red validation errors
      render :new, status: :unprocessable_entity
    end
  end

end
