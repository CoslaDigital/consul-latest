Rails.root.join("app", "controllers", "organizations", "registrations_controller.rb")
class Organizations::RegistrationsController < Devise::RegistrationsController
  invisible_captcha only: [:create], honeypot: :address, scope: :user

  def create
    build_resource(sign_up_params)
    if resource.valid?
      super do |user|
        # Removes unuseful "organization is invalid" error message
        user.errors.delete(:organization)
        
        if user.persisted?
        user.send_new_organization_admin_notification!
        end
      end
    else
      render :new
    end
  end

end
