load Rails.root.join("app", "helpers", "application_helper.rb")
# File: app/helpers/custom/application_helper.rb
module Custom::ApplicationHelper

  # Checks if the Young Scot card number prefixes are configured in secrets.
  # @return [Boolean] true if prefixes are present, false otherwise.
  def ys_configured?
    Setting.enable_card_login?
    end
 end
