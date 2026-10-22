class Verification::YsDemographic
  include ActiveModel::Model

  attr_accessor :user, :date_of_birth, :postal_code, :terms_of_service

  validates :date_of_birth, presence: true
  validates :postal_code, presence: true
  validates :terms_of_service, acceptance: { allow_nil: false }

  validate :allowed_age
  validate :local_postal_code

  def save
    return false unless valid?

    # 1. Calculate Geozone in memory
    normalized_postcode = postal_code.to_s.strip.downcase
    new_geozone_id = Postcode.find_geozone_for_postcode(normalized_postcode) || user.geozone_id

    # 2. Update the user with the Geozone and Timestamp ONLY.
    # Do NOT save the raw date_of_birth or postal_code.
    user.update!(
      geozone_id: new_geozone_id,
      verified_at: Time.current
    )
  end

  private

    def allowed_age
      return if errors[:date_of_birth].any?

      # We cast it to a Date object in memory for the age check
      dob_in_memory = date_of_birth.is_a?(String) ? Date.parse(date_of_birth) : date_of_birth

      if Age.in_years(dob_in_memory) < User.minimum_required_age
        errors.add(:date_of_birth, I18n.t("verification.residence.new.error_not_allowed_age"))
      end
    rescue ArgumentError
      errors.add(:date_of_birth, "is invalid")
    end

    def local_postal_code
      return if Setting["postal_codes"].blank?

      is_valid = Setting["postal_codes"].split(",").any? do |code_or_range|
        if code_or_range.include?(":")
          Range.new(*code_or_range.split(":").map(&:strip)).include?(postal_code&.strip)
        else
          /\A#{code_or_range.strip}\Z/.match?(postal_code&.strip)
        end
      end

      unless is_valid
        errors.add(:postal_code, I18n.t("verification.residence.new.error_not_allowed_postal_code"))
      end
    end
end
