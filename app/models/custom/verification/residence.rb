load Rails.root.join("app", "models", "verification", "residence.rb")

class Verification::Residence
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations::Callbacks

  attribute :date_of_birth, :date
  attr_accessor :user, :document_number, :document_type, :date_of_birth, :postal_code, :terms_of_service

  # --- 1. WIPE OUT ALL ORIGINAL CONSUL VALIDATIONS ---
  clear_validators!
  reset_callbacks(:validate)
  # ---------------------------------------------------

  # --- 2. RE-DECLARE ONLY THE ONES YOU ACTUALLY WANT ---
  validates :date_of_birth, presence: true, if: -> { Setting["min_age_to_participate"].present? }
  validates :postal_code, presence: true
  validates :terms_of_service, acceptance: { allow_nil: false }

  validate :allowed_age, if: -> { Setting["min_age_to_participate"].present? }
  validate :local_postal_code
  # -----------------------------------------------------

  def initialize(attrs = {})
    super
  end

  def save
    return false unless valid?

    user.update(
      geozone_id: my_geozone,
      date_of_birth: date_of_birth.present? ? date_of_birth.in_time_zone.to_datetime : nil,
      residence_verified_at: Time.current,
      verified_at: Time.current
    )
  end

  def save!
    validate! && save
  end

  def allowed_age
    return if errors[:date_of_birth].any? || Age.in_years(Date.parse(date_of_birth)) >= User.minimum_required_age

    errors.add(:date_of_birth, I18n.t("verification.residence.new.error_not_allowed_age"))
  end

  def store_failed_attempt
    FailedCensusCall.create(
      user: user,
      document_number: document_number,
      document_type: document_type,
      date_of_birth: date_of_birth,
      postal_code: postal_code
    )
  end

  def my_geozone
    # 1. Short-circuit: If they already have a 'ys' geozone, skip the lookup entirely and keep it.
    # The `&.` operator safely handles cases where the user doesn't have a geozone yet.
    if user.geozone&.name&.to_s&.start_with?("ys")
      Rails.logger.info("Skipping postcode lookup: User already has YS geozone (#{user.geozone.name})")
      return user.geozone_id
    end

    # 2. Otherwise, attempt to find the geozone via postcode
    geozone_id = nil
    if postal_code.present?
      Rails.logger.info("About to check postcode: #{postal_code}")
      geozone_id = Postcode.find_geozone_for_postcode(postal_code)
    end

    geozone_id
  end

  def verify_dob
    Setting["min_age_to_participate"].present?
  end

  def local_postal_code
    errors.add(:postal_code, I18n.t("verification.residence.new.error_not_allowed_postal_code")) unless valid_postal_code?
  end

  private

    def valid_postal_code?
      return true if Setting["postal_codes"].blank?

      Setting["postal_codes"].split(",").any? do |code_or_range|
        if code_or_range.include?(":")
          Range.new(*code_or_range.split(":").map(&:strip)).include?(postal_code&.strip)
        else
          /\A#{code_or_range.strip}\Z/.match?(postal_code&.strip)
        end
      end
    end
end
