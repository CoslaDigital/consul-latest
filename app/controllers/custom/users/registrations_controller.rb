load Rails.root.join("app", "controllers", "users", "registrations_controller.rb").to_s

class Users::RegistrationsController < Devise::RegistrationsController

  # We overwrite ONLY the create method. All other methods (new, delete, finish_signup, etc.)
  # are inherited from the base file we loaded above.
  def create
    build_resource(sign_up_params)

    # Custom flag required by Consul
    resource.registering_from_web = true

    # 1. Bypass `super` to avoid Devise triggering `build_resource` a second time,
    # which would erase our `registering_from_web` flag.
    resource.save
    yield resource if block_given?

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
    else
      # 2. Cleanup passwords so they aren't returned in plain text on error
      clean_up_passwords resource
      set_minimum_password_length if respond_to?(:set_minimum_password_length)

      # 3. CRITICAL FIX: Guarantee 422 status so Turbo/Hotwire displays the error messages
      render :new, status: :unprocessable_entity
    end
  end

end
