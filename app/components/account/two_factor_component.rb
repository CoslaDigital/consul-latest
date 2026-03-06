# app/components/account/two_factor_component.rb
class Account::TwoFactorComponent < ApplicationComponent
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def render?
    two_factor_configured?
  end

  private

    def two_factor_configured?
      secrets = Tenant.current_secrets
      secrets[:devise_otp_key].present? &&
        secrets.dig(:active_record_encryption, :primary_key).present? &&
        secrets.dig(:active_record_encryption, :deterministic_key).present? &&
        secrets.dig(:active_record_encryption, :key_derivation_salt).present?
    end
end
