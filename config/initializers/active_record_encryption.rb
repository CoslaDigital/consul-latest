# config/initializers/active_record_encryption.rb
Rails.application.config.after_initialize do
  encryption_config = Rails.application.secrets[:active_record_encryption]

  if encryption_config.present? &&
     encryption_config[:primary_key].present? &&
     encryption_config[:deterministic_key].present? &&
     encryption_config[:key_derivation_salt].present?

    ActiveRecord::Encryption.configure(
      primary_key: encryption_config[:primary_key],
      deterministic_key: encryption_config[:deterministic_key],
      key_derivation_salt: encryption_config[:key_derivation_salt]
    )

    Rails.logger.info "✅ ActiveRecord encryption configured from secrets.yml"
  else
    Rails.logger.warn "⚠️  ActiveRecord encryption keys not found in secrets.yml"
  end
end
