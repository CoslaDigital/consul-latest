load Rails.root.join("app", "models", "user.rb")

class User < ApplicationRecord
  DOCUMENT_ID_STRATEGIES = [
    :valid_ys_document?, # original young scot logic
    :valid_na_document?
  ].freeze

  NEC_PREFIX_MAPPING = {
    # Aberdeen City
    "633560" => "aberdeen_city", # CONFLICT WARNING: Was 'inverclyde' in original mapping
    "633718" => "aberdeen_city",

    # Aberdeenshire
    "633727" => "aberdeenshire",

    # Angus
    "633719" => "angus",

    # Argyll and Bute
    "633297" => "argyll_and_bute", # Added from new list
    "633644" => "argyll_and_bute",

    # City of Edinburgh
    "633668" => "city_of_edinburgh",

    # Clackmannanshire
    "633741" => "clackmannanshire",

    # Comhairle nan Eilean Siar (Western Isles)
    "633624" => "western_isles",

    # Dumfries and Galloway
    "633670" => "dumfries_and_galloway",

    # Dundee City
    "633720" => "dundee_city",
    "633725" => "dundee_city", # Added from new list

    # East Ayrshire
    "633687" => "east_ayrshire", # Added from new list
    "633728" => "east_ayrshire",

    # East Dunbartonshire
    "633564" => "east_dunbartonshire", # Added from new list
    "633590" => "east_dunbartonshire",
    "633597" => "east_dunbartonshire",

    # East Lothian
    "633546" => "east_lothian",
    "633675" => "east_lothian",

    # East Renfrewshire
    "633570" => "east_renfrewshire",

    # Falkirk
    "633733" => "falkirk",

    # Fife
    "633250" => "fife",

    # Glasgow City
    "633740" => "glasgow_city",

    # Highland
    "633603" => "highland",

    # Inverclyde
    "633744" => "inverclyde", # Added from new list (Replaced 633560)

    # Midlothian
    "633678" => "midlothian",

    # Moray
    "633604" => "moray",
    "633737" => "moray", # Added from new list

    # North Ayrshire
    "633279" => "north_ayrshire",
    "633680" => "north_ayrshire",

    # North Lanarkshire
    "633284" => "north_lanarkshire",

    # Orkney Islands
    "633605" => "orkney_islands",
    "633734" => "orkney_islands", # Added from new list

    # Perth and Kinross
    "633708" => "perth_and_kinross", # Added from new list
    "633722" => "perth_and_kinross",

    # Renfrewshire
    "633289" => "renfrewshire",

    # Scottish Borders
    "633743" => "scottish_borders",

    # Shetland Islands
    "633606" => "shetland_islands",
    "633679" => "shetland_islands", # Added from new list

    # South Ayrshire
    "633559" => "south_ayrshire", # Added from new list
    "633682" => "south_ayrshire",

    # South Lanarkshire
    "633231" => "south_lanarkshire",

    # Stirling
    "633739" => "stirling",

    # West Dunbartonshire
    "633511" => "west_dunbartonshire", # Added from new list
    "633580" => "west_dunbartonshire",

    # West Lothian
    "633285" => "west_lothian", # Added from new list
    "633676" => "west_lothian",

    # Trumptonshire (Mock/Test)
    "999111" => "trumptonshire"
  }.freeze

  has_one :process_manager
  scope :process_managers, -> { joins(:process_manager) }

  # 1. Registration Restriction
  validate :email_belongs_to_allowed_domain, if: -> { email.present? && email_changed? }

  # 2. Login Restriction
  def active_for_authentication?
    super && allowed_email_domain?
  end

  # Provide a specific error message when login fails due to domain
  def inactive_message
    allowed_email_domain? ? super : :unauthorized_domain
  end

  def masked_username
    return username if username.blank?
    if username.length <= 4
      username.gsub(/(?<=.).(?=.)/, '*')
    else
      username.gsub(/\A(..)(.*)(..)\z/) { "#{$1}#{'*' * $2.length}#{$3}" }
    end
  end

  def process_manager?
    process_manager.present?
  end

  def administrator?
    administrator.present?
  end

  def self.unlock_in
    security = Tenant.current_secrets[:security]
    lockable = security[:lockable] if security
    unlock_in_value = lockable[:unlock_in] if lockable
    (unlock_in_value || 10).to_f.minutes
  end

  def erase(erase_reason = nil)
    update!(
      erased_at: Time.current,
      erase_reason: erase_reason,
      username: nil,
      document_number: nil,
      email: nil,
      unconfirmed_email: nil,
      phone_number: nil,
      encrypted_password: "",
      confirmation_token: nil,
      reset_password_token: nil,
      email_verification_token: nil,
      confirmed_phone: nil,
      unconfirmed_phone: nil
    )
    identities.destroy_all
    remove_roles
  end

  def self.first_or_initialize_for_oauth(auth)
    oauth_email = auth.info.email
    auth.info.verified || auth.info.verified_email || auth.info.email_verified || auth.extra.raw_info.email_verified
    oauth_email_confirmed = oauth_email.present?
    oauth_user = User.find_by(email: oauth_email) if oauth_email_confirmed

    oauth_user || User.new(
      username: auth.info.name || auth.uid,
      email: oauth_email,
      oauth_email: oauth_email,
      password: Devise.friendly_token[0, 20],
      terms_of_service: "1",
      confirmed_at: oauth_email_confirmed ? DateTime.current : nil,
      level_two_verified_at: DateTime.current
    )
  end

  def self.extract_saml_attributes(auth)
    attribute_mapping = {
      "saml_username" => "urn:oid:0.9.2342.19200300.100.1.1",
      "saml_authority_code" => "urn:oid:0.9.2342.19200300.100.1.17",
      "saml_firstname" => "urn:oid:0.9.2342.19200300.100.1.2",
      "saml_surname" => "urn:oid:0.9.2342.19200300.100.1.4",
      "saml_latitude" => "urn:oid:0.9.2342.19200300.100.1.33",
      "saml_longitude" => "urn:oid:0.9.2342.19200300.100.1.34",
      "saml_date_of_birth" => "urn:oid:0.9.2342.19200300.100.1.8",
      "saml_gender" => "urn:oid:0.9.2342.19200300.100.1.9",
      "saml_postcode" => "urn:oid:0.9.2342.19200300.100.1.16",
      "saml_email" => "urn:oid:0.9.2342.19200300.100.1.22",
      "saml_town" => "urn:oid:0.9.2342.19200300.100.1.15",
      "saml_add1" => "urn:oid:0.9.2342.19200300.100.1.12",
      "saml_5" => "urn:oid:0.9.2342.19200300.100.1.5",
      "saml_6" => "urn:oid:0.9.2342.19200300.100.1.6",
      "saml_7" => "urn:oid:0.9.2342.19200300.100.1.7",
      "saml_assurance" => "urn:oid:0.9.2342.19200300.100.1.20",
      "saml_10" => "urn:oid:0.9.2342.19200300.100.1.10"
    }

    attributes = auth.extra.raw_info.attributes
    extracted_values = {}

    attribute_mapping.each do |attribute_name, oid_value|
      if attributes[oid_value]
        extracted_values[attribute_name] = attributes[oid_value][0]
      end
    end

    extracted_values
  end

  def self.first_or_initialize_for_saml(auth)
    extracted_values = extract_saml_attributes(auth)
    saml_username = extracted_values["saml_username"]
    saml_firstname = extracted_values["saml_firstname"]
    saml_surname = extracted_values["saml_surname"]
    saml_date_of_birth = extracted_values["saml_date_of_birth"]
    saml_gender = extracted_values["saml_gender"]
    saml_postcode = extracted_values["saml_postcode"]
    saml_email = extracted_values["saml_email"]

    oauth_email = saml_email
    saml_full_name = saml_firstname + "_" + saml_surname
    saml_email_confirmed = saml_email.present?

    normalized_saml_postcode = saml_postcode.strip.downcase if saml_postcode.present?
    existing_user = User.find_by(email: saml_email)
    new_geozone_id = Postcode.find_geozone_for_postcode(normalized_saml_postcode)

    if existing_user && new_geozone_id && new_geozone_id != existing_user.geozone_id
      existing_user.update(geozone_id: new_geozone_id)
      Rails.logger.info("User geozone updated to #{new_geozone_id}")
    end

    oauth_user = User.find_by(email: saml_email) if saml_email_confirmed
    saml_geozone_id = nil

    if normalized_saml_postcode.present?
      saml_geozone_id = Postcode.find_geozone_for_postcode(normalized_saml_postcode)
    end

    if saml_username.present? && saml_username != saml_email && saml_username != saml_full_name
      oauth_username = saml_username
    else
      oauth_username = "#{saml_full_name}_#{rand(100..999)}"
    end

    oauth_user || User.new(
      username: oauth_username,
      email: saml_email,
      date_of_birth: saml_date_of_birth,
      gender: saml_gender,
      password: Devise.friendly_token[0, 20],
      terms_of_service: "1",
      confirmed_at: DateTime.current,
      geozone_id: saml_geozone_id
    )
  end

  def update_user_details_from_saml(auth)
    extracted_values = self.class.extract_saml_attributes(auth)
    saml_postcode = extracted_values["saml_postcode"]
    normalized_saml_postcode = saml_postcode.strip.downcase if saml_postcode.present?
    new_geozone_id = Postcode.find_geozone_for_postcode(normalized_saml_postcode)

    self.geozone_id = new_geozone_id if geozone_id != new_geozone_id
    save if changed?
  end

  def send_new_organization_admin_notification!
    unless persisted? && organization.present? && organization.persisted?
      Rails.logger.warn "[User##{id}] Skipping AdminNotification: User or Organization not fully persisted."
      return
    end

    alert_title = "New Organization Registered: #{organization.name}"
    alert_body = "Organization '#{organization.name}' (Responsible: #{organization.responsible_name || "N/A"}) " \
      "was registered by user #{email} (Phone: #{phone_number || "N/A"})."

    begin
      admin_link = Rails.application.routes.url_helpers.admin_organizations_path(host: ENV["APPLICATION_HOST"])
    rescue NoMethodError, ActionController::UrlGenerationError => e
      admin_link = "/admin/organizations"
    end

    admin_notification = AdminNotification.new(
      title: alert_title,
      body: alert_body,
      segment_recipient: "administrators",
      link: admin_link
    )

    if admin_notification.save
      admin_notification.deliver
    else
      Rails.logger.error "[User##{id}] Failed to save AdminNotification: #{admin_notification.errors.full_messages.join(", ")}"
    end
  rescue StandardError => e
    Rails.logger.error "[User##{id}] Error in send_new_organization_admin_notification!: #{e.message}"
  end

  def self.find_for_database_authentication(warden_conditions)
    conditions = warden_conditions.dup
    login = conditions.delete(:login)

    # Extract the email address from the Devise login form payload
    form_email = conditions.delete(:email)

    if validate_document_number(login) && !Setting.enable_card_login?
      return nil
    end

    user = where(conditions.to_hash).find_by(["lower(email) = ?", login.downcase]) ||
           where(conditions.to_hash).find_by(["username = ?", login]) ||
           where(conditions.to_hash).find_by(["confirmed_phone = ?", login]) ||
           where(conditions.to_hash).find_by(["document_number = ?", login])

    # BACKFILL CAPTURE: If a legacy user logs in without an email, but typed one into the form, save it.
    if user.present? && user.email.blank? && form_email.present?
      user.update_column(:email, form_email)
    end

    if user.nil? && validate_document_number(login) && Setting.enable_card_login?
      # Pass the captured email into the creation logic
      user = log_in_or_create_ys_user(login, form_email)
      # Prevent Devise from attempting to authenticate an unpersisted user object
      user = nil unless user&.persisted?
    end

    user
  end

  def applicable_geozone_ids
    return [] unless geozone.present?
    ancestors = geozone.self_and_ancestor_ids
    descendants = geozone.self_and_descendant_ids
    (ancestors + descendants).uniq
  end

  # ==========================================
  # PUBLIC PIPELINE METHODS (Must be above private)
  # ==========================================

  def verification_pipeline
    steps = []

    if Setting["verification.require_residence"].present?
      if User.valid_ys_document?(document_number)
        if Setting["verification.ys_requires_demographics"].present?
          steps << :ys_demographics
        end
      else
        steps << :residence
      end
    end

    if Setting["verification.require_sms"].present? && Tenant.current_secrets&.sms_api_key.present?
      steps << :sms
    end

    if Setting["verification.require_letter"].present?
      steps << :letter
    end

    steps
  end

  def pending_verification_steps

    return [] if Setting["feature.user.skip_verification"].present?

    verification_pipeline.reject do |step|
      case step
      when :ys_demographics then residence_verified_at.present?
      when :residence then residence_verified_at.present?
      when :sms then confirmed_phone.present?
      when :letter then verified_at.present?
      else true
      end
    end
  end

  def pipeline_complete?
    pending_verification_steps.empty?
  end

  def promote_to_fully_verified!
    updates = {}
    updates[:residence_verified_at] = Time.current unless residence_verified_at?
    updates[:level_two_verified_at] = Time.current unless level_two_verified_at?
    updates[:verified_at] = Time.current unless verified_at?

    update_columns(updates) if updates.any?
  end

  # --- CONSUL OVERRIDES ---
  def level_two_verified?
    super || pipeline_complete?
  end

  def residence_verified?
    super || pipeline_complete?
  end

  def level_three_verified?
    super || pipeline_complete?
  end

  def unverify!
    update!(
      residence_verified_at: nil,
      level_two_verified_at: nil,
      verified_at: nil,
      confirmed_phone: nil,
      unconfirmed_phone: nil,
      sms_confirmation_code: nil,
      document_number: nil,
      document_type: nil,
      letter_requested_at: nil,
      letter_verification_code: nil
    )
  end

  # ==========================================
  # PRIVATE METHODS
  # ==========================================
  private

    def self.log_in_or_create_ys_user(document_number, email_address = nil)
      prefix = document_number.to_s[0, 6]
      council_name = council_name_for_prefix(prefix)
      expected_geozone = Geozone.find_by(name: "ys_#{council_name}")

      # 1. Exact Match Fallback
      if (existing_user = User.find_by(username: document_number))
        if expected_geozone && existing_user.geozone_id != expected_geozone.id
          existing_user.geozone_id = expected_geozone.id
          existing_user.save(validate: false)
        end
        return existing_user
      end

      # 2. Legacy User Match
      if valid_ys_document?(document_number)
        base_number = document_number.to_s[0, 14]
        if (legacy_user = User.where("document_number LIKE ?", "#{base_number}%").first)
          legacy_user.skip_reconfirmation! if legacy_user.respond_to?(:skip_reconfirmation!)
          legacy_user.skip_confirmation_notification! if legacy_user.respond_to?(:skip_confirmation_notification!)

          legacy_user.username = document_number
          legacy_user.document_number = document_number
          legacy_user.password = document_number

          # Update email if they provided one and don't already have one
          legacy_user.email = email_address if legacy_user.email.blank? && email_address.present?

          if expected_geozone && legacy_user.geozone_id != expected_geozone.id
            legacy_user.geozone_id = expected_geozone.id
          end

          if legacy_user.save(validate: false)
            return legacy_user
          end
        end
      end

      # 3. Create Brand New User
      user = User.new(
        username: document_number,
        password: document_number,
        document_number: document_number,
        geozone_id: expected_geozone&.id,
        terms_of_service: "1"
      )

      # Determine if email confirmation is required via Admin Settings
      if Setting["verification.require_email_confirmation"].present?
        user.email = email_address # Confirmed_at remains nil to trigger email flow
      else
        user.email = email_address if email_address.present?
        user.confirmed_at = Time.current # Instantly bypass email confirmation
        user.skip_confirmation_notification! if user.respond_to?(:skip_confirmation_notification!)
      end

      # 4. Pipeline Toggles (Bypass Demographics if disabled)
      if Setting["feature.user.skip_verification"].present?
        user.verified_at = Time.current
        user.level_two_verified_at = Time.current
        user.residence_verified_at = Time.current
      elsif !Setting["verification.ys_requires_demographics"].present?
        user.residence_verified_at = Time.current
      end

      user.valid?
      # FIX: If the admin toggle is OFF, explicitly delete Devise's missing email complaints
      # so the YS account can save successfully without an email address.
      unless Setting["verification.require_email_confirmation"].present?
        user.errors.delete(:email)
      end

      # Check if there are any *other* errors preventing save (excluding password)
      other_errors = user.errors.messages.except(:password)
      if other_errors.empty?
        if user.save(validate: false)
          user.errors.clear
          return user
        end
      else
        Rails.logger.error("Failed to create YS user #{document_number}: #{other_errors}")
      end

      nil
    end

    def self.ys_document_error_message(document_number)
      return "Please enter your card number." if document_number.blank?
      str_number = document_number.to_s
      if str_number.length != 16
        return "The number you entered is not valid. Please enter a valid 16-digit card number."
      end

      prefix = str_number[0, 6]
      council_name = council_name_for_prefix(prefix)
      unless council_name
        return "We do not recognize the prefix of this card number. Please check for typos."
      end

      expected_geozone = "ys_#{council_name}"
      unless Geozone.exists?(name: expected_geozone)
        formatted_council = council_name.to_s.titleize.gsub("_", " ")
        return "Your card is valid, but belongs to #{formatted_council}, which is not currently participating on this platform."
      end

      "The format of your card number is invalid. Please ensure there are no letters or special characters."
    end

    def self.validate_document_number(document_number)
      return false if document_number.blank?
      DOCUMENT_ID_STRATEGIES.any? do |strategy|
        if strategy.is_a?(Regexp)
          document_number.to_s.match?(strategy)
        elsif strategy.is_a?(Symbol) && respond_to?(strategy)
          send(strategy, document_number)
        end
      end
    end

    def self.valid_ys_document?(document_number)
      return false unless document_number.to_s.length == 16

      prefix = document_number.to_s[0, 6]
      middle = document_number.to_s[6, 8]
      suffix = document_number.to_s[14, 2]

      council_name = council_name_for_prefix(prefix)
      return false unless council_name

      expected_geozone = "ys_#{council_name}"
      return false unless Geozone.exists?(name: expected_geozone)

      temp_code = ENV.fetch("YS_TEMP_CODE", "XX")
      valid_middle = middle.match?(/\A(\d{2}|#{Regexp.escape(temp_code)})\d{6}\z/i)
      valid_suffix = suffix.match?(/\A0[0-5]\z/)

      valid_middle && valid_suffix
    end

    def self.valid_na_document?(document_number)
      allowed_formats = [
        /\AON0\d{4,14}\z/,
        /\A[Pp]0\d{5,9}[a-zA-Z0-9]\z/
      ]
      allowed_formats.any? { |regex| document_number.to_s.match?(regex) }
    end

    def allowed_email_domain?
      return true unless Setting["feature.restrict_login_to_officials"]
      return true if administrator?

      allowed_domain = Setting["email_domain_for_officials"].to_s.strip.downcase.sub(/\A@/, "")
      return true if allowed_domain.blank?
      return false if email.blank?

      user_domain = email.split('@').last.downcase
      user_domain == allowed_domain || user_domain.end_with?(".#{allowed_domain}")
    end

    def email_belongs_to_allowed_domain
      unless allowed_email_domain?
        errors.add(:email, "must belong to the authorized domain (#{Setting['email_domain_for_officials']})")
      end
    end

    def bulk_verify!
      self.verified_at = Time.current
      self.residence_verified_at = Time.current
      self.confirmed_at = Time.current

      self.skip_confirmation_notification! if respond_to?(:skip_confirmation_notification!)
      self.skip_reconfirmation! if respond_to?(:skip_reconfirmation!)

      self.terms_of_service = '1'
      self.email = nil if email.blank?

      self.save!
    end

    def self.council_name_for_prefix(prefix)
      core_council = NEC_PREFIX_MAPPING[prefix.to_s]
      return core_council if core_council.present?

      secrets = Tenant.current_secrets || {}
      temp_mappings = secrets[:temp_nec_mappings] || []
      lookup_hash = temp_mappings.map(&:to_s).each_slice(2).to_h

      lookup_hash[prefix.to_s]
    end

end
