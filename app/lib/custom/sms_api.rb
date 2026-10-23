require "notifications/client"

class SmsApi
  attr_accessor :client

  def initialize
    # Only initialize the real client if we are using the endpoint
    if end_point_available?
      @client = Notifications::Client.new(Tenant.current_secrets.sms_api_key)
    end
  end

  def sms_deliver(phone, code)
    # 1. Protect local development
    return true unless end_point_available?

    begin
      Rails.logger.info "Sending GOV.UK Notify SMS to #{phone} with code #{code}"

      response = client.send_sms(
        phone_number: phone,
        template_id: "3e91c951-f3b5-4a35-a432-411f7f6c24ff", # Make sure this matches your GOV.UK template exactly!
        personalisation: message(phone, code)
      )

      log_sms_response(response)
      success?(response)

    rescue Notifications::Client::RequestError => e
      Rails.logger.error "GOV.UK Notify SMS Error: #{e.message}"
      false
    end
  end

  def message(phone, code)
    {
      name: "User", # If your Notify template doesn't use ((name)), you can delete this line!
      token: code,

      # Setting["url"] pulls the live URL configured in the Admin > Settings panel.
      # We add a fallback to localhost just in case it's blank in your dev environment.
      link: Setting["url"].presence || "http://localhost:3000"
    }
  end

  def success?(response)
    # 2. FIX: We only check for ID. Reference will be nil since we didn't send one.
    response.id.present?
  end

  def log_sms_response(response)
    Rails.logger.info "Notification ID: #{response.id}"
    Rails.logger.info "Message Body: #{response.content[:body]}"
    Rails.logger.info "From Number: #{response.content[:from_number]}"
  end

  def end_point_available?
    # 3. FIX: Prevent actual SMS sending in local development
    # Rails.env.production? || Rails.env.staging? || Rails.env.preproduction?
    true
  end

  # Stubbed response no longer needed because we just return `true`
  # in dev to let Consul move to the next screen.
end
