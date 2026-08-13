load Rails.root.join("app", "models", "user.rb")

class User < ApplicationRecord
  DOCUMENT_ID_STRATEGIES = [
    :valid_ys_document?, # original young scot logic
    :valid_na_document?
  ].freeze

  NEC_PREFIX_MAPPING = {
    "633718" => "aberdeen_city",
    "633727" => "aberdeenshire",
    "633719" => "angus",
    "633644" => "argyll_and_bute",
    "633668" => "city_of_edinburgh",
    "633741" => "clackmannanshire",
    "633624" => "western_isles", # Comhairle nan Eilean Siar
    "633670" => "dumfries_and_galloway",
    "633720" => "dundee_city",
    "633728" => "east_ayrshire",
    "633590" => "east_dunbartonshire",
    "633675" => "east_lothian",
    "633570" => "east_renfrewshire",
    "633733" => "falkirk",
    "633250" => "fife",
    "633740" => "glasgow_city",
    "633603" => "highland",
    "633560" => "inverclyde",
    "633678" => "midlothian",
    "633604" => "moray",
    "633680" => "north_ayrshire",
    "633284" => "north_lanarkshire",
    "633605" => "orkney_islands",
    "633722" => "perth_and_kinross",
    "633289" => "renfrewshire",
    "633743" => "scottish_borders",
    "633606" => "shetland_islands",
    "633682" => "south_ayrshire",
    "633231" => "south_lanarkshire",
    "633739" => "stirling",
    "633580" => "west_dunbartonshire",
    "633676" => "west_lothian",
    "999111" => "trumptonshire"
  }.freeze

  has_one :process_manager
  scope :process_managers, -> { joins(:process_manager) }


  def masked_username
    return username if username.blank?
    # If the username is 4 characters or less, just mask the middle
    if username.length <= 4
      username.gsub(/(?<=.).(?=.)/, '*')
    else
      # Keeps first 2 and last 2, masks the rest
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

  def send_devise_notification(notification, *)
    devise_mailer.send(notification, self, *).deliver_later
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

  # Get the existing user by email if the provider gives us a verified email.
  def self.first_or_initialize_for_oauth(auth)
    oauth_email = auth.info.email
    oauth_verified = auth.info.verified || auth.info.verified_email || auth.info.email_verified || auth.extra.raw_info.email_verified
    oauth_email_confirmed = oauth_email.present? #&& oauth_verified
    oauth_user = User.find_by(email: oauth_email) if oauth_email_confirmed

    oauth_user || User.new(
      username: auth.info.name || auth.uid,
      email: oauth_email,
      oauth_email: oauth_email,
      password: Devise.friendly_token[0, 20],
      terms_of_service: "1",
      confirmed_at: oauth_email_confirmed ? DateTime.current : nil,
      level_two_verified_at: DateTime.current,
    #  residence_verified_at:  DateTime.current
    )
  end

  def self.extract_saml_attributes(auth)
    # Define the attribute mapping here or in a constant
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

    # Assuming 'auth.extra.raw_info' is the OneLogin::RubySaml::Attributes object
    attributes = auth.extra.raw_info.attributes

    # Initialize a hash to store the extracted values
    extracted_values = {}

    # Iterate through the attribute mapping and extract values
    attribute_mapping.each do |attribute_name, oid_value|
      if attributes[oid_value]
        extracted_values[attribute_name] = attributes[oid_value][0]
      end
    end

    extracted_values
  end

  def self.first_or_initialize_for_saml(auth)
    extracted_values = extract_saml_attributes(auth)

    # Now you have a hash containing the extracted values
    # Rails.logger.info("extracted values: #{extracted_values.inspect}")

    # Assuming 'extracted_values' is the hash containing extracted values
    saml_username = extracted_values["saml_username"]
    saml_authority_code = extracted_values["saml_authority_code"]
    saml_firstname = extracted_values["saml_firstname"]
    saml_surname = extracted_values["saml_surname"]
    saml_long = extracted_values["saml_longitude"]
    saml_lat = extracted_values["saml_latitude"]
    saml_date_of_birth = extracted_values["saml_date_of_birth"]
    saml_gender = extracted_values["saml_gender"]
    saml_postcode = extracted_values["saml_postcode"]
    saml_email = extracted_values["saml_email"]
    saml_town = extracted_values["saml_town"]

    oauth_email = saml_email
    oauth_gender = saml_gender
    oauth_username = saml_username
    oauth_lacode = saml_authority_code
    saml_full_name = saml_firstname + "_" + saml_surname
    oauth_date_of_birth = saml_date_of_birth
    oauth_email_confirmed = oauth_email.present?
    saml_email_confirmed = saml_email.present?

    # Normalize the saml_postcode by stripping spaces and converting to lowercase
    normalized_saml_postcode = saml_postcode.strip.downcase if saml_postcode.present?

    # Find existing user based on the current email (before potential update)
    existing_user = User.find_by(email: saml_email)
    # Find the Geozone ID for the new postcode
    new_geozone_id = Postcode.find_geozone_for_postcode(normalized_saml_postcode)
    # Update the user's geozone if it has changed (based on geozone ID comparison)
    if existing_user && new_geozone_id && new_geozone_id != existing_user.geozone_id
      existing_user.update(geozone_id: new_geozone_id)
      Rails.logger.info("User geozone updated to #{new_geozone_id}")
    end

    # lacode comes from list of councils registered with IS
    oauth_lacode_ref = "9079" # this should be picked up from secrets in future
    oauth_lacode_confirmed = oauth_lacode == oauth_lacode_ref
    oauth_user = User.find_by(email: saml_email) if saml_email_confirmed

    # Initialize saml_geozone_id
    saml_geozone_id = nil
    # Assign Geozone based on the normalized saml_postcode if it exists
    if normalized_saml_postcode.present? # Find the Postcode instance based on the normalized saml_postcode
      puts "about to check: #{normalized_saml_postcode}"
      saml_geozone_id = Postcode.find_geozone_for_postcode(normalized_saml_postcode)
    end

    # oauth_username = oauth_full_name ||  oauth_email.split("@").first || auth.info.name || auth.uid
    if saml_username.present? && saml_username != saml_email && saml_username != saml_full_name
      oauth_username = saml_username
    else
      # If the original value of oauth_username is the same as oauth_email or oauth_full_name, add a random number to obfuscate
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
      #      verified_at: DateTime.current ,
      #      residence_verified_at:  DateTime.current,
      geozone_id: saml_geozone_id
    )
  end

  # Method to update user attributes based on SAML data
  def update_user_details_from_saml(auth)
    extracted_values = self.class.extract_saml_attributes(auth)

    Rails.logger.info("extracted values: #{extracted_values.inspect}")
    saml_date_of_birth = extracted_values["saml_date_of_birth"]
    saml_gender = extracted_values["saml_gender"]
    saml_postcode = extracted_values["saml_postcode"]
    # Normalize the saml_postcode by stripping spaces and converting to lowercase
    normalized_saml_postcode = saml_postcode.strip.downcase if saml_postcode.present?

    # Find the Geozone ID for the new postcode
    new_geozone_id = Postcode.find_geozone_for_postcode(normalized_saml_postcode)

    # Check and update the user's details if they have changed
    self.geozone_id = new_geozone_id if geozone_id != new_geozone_id
    # Add more fields if necessary

    # Save only if any changes have been made
    save if changed?
  end

  # send the notification using AdminNotification system
  def send_new_organization_admin_notification!
    # Ensure the user and their organization are actually created and persisted
    unless persisted? && organization.present? && organization.persisted?
      Rails.logger.warn "[User##{id}] Skipping AdminNotification: User or Organization not fully persisted."
      return
    end

    # Construct the title and body for the notification
    alert_title = "New Organization Registered: #{organization.name}"
    alert_body = "Organization '#{organization.name}' (Responsible: #{organization.responsible_name || "N/A"}) " \
      "was registered by user #{email} (Phone: #{phone_number || "N/A"})."

    begin
      admin_link = Rails.application.routes.url_helpers.admin_organizations_path(host: ENV["APPLICATION_HOST"])
    rescue NoMethodError, ActionController::UrlGenerationError => e
      Rails.logger.warn "[User##{id}] Could not generate admin_organization_path for Org ID #{organization.id}: #{e.message}. Using a fallback link."
      admin_link = "/admin/organizations" # Basic fallback
    end

    # Create and deliver the AdminNotification
    admin_notification = AdminNotification.new(
      title: alert_title,
      body: alert_body,
      segment_recipient: "administrators",
      link: admin_link
    )

    if admin_notification.save
      admin_notification.deliver
      Rails.logger.info "[User##{id}] AdminNotification for new organization #{organization.id} created and delivery initiated."
    else
      Rails.logger.error "[User##{id}] Failed to save AdminNotification for new organization: #{admin_notification.errors.full_messages.join(", ")}"
    end

  rescue StandardError => e
    # Catch potential errors during the process
    Rails.logger.error "[User##{id}] Error in send_new_organization_admin_notification! for Org ID #{organization&.id}: #{e.class.name} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  # overwriting of Devise method to allow login using email OR username
  def self.find_for_database_authentication(warden_conditions)
    conditions = warden_conditions.dup
    login = conditions.delete(:login)
    user = where(conditions.to_hash).find_by(["lower(email) = ?", login.downcase]) ||
           where(conditions.to_hash).find_by(["username = ?", login]) ||
           where(conditions.to_hash).find_by(["confirmed_phone = ?", login]) ||
           where(conditions.to_hash).find_by(["document_number = ?", login])

    if user.nil? && validate_document_number(login)
      # If no user is found and the login is a valid document, create a new user
      user = log_in_or_create_ys_user(login)
    end
    user
  end

  private

    def self.log_in_or_create_ys_user(username)
      if (existing_user = User.find_by(username: username))
        return existing_user
      end

      prefix = username.to_s[0, 6]
      council_name = NEC_PREFIX_MAPPING[prefix]
      geozone_name = "ys_#{council_name}"

      user = User.new(
        username: username,
        email: "#{username}@consul.dev",
        password: username,
        document_number: username,
        geozone_id: Geozone.find_by!(name: geozone_name).id,
        terms_of_service: "1",
        confirmed_at: Time.current,
        verified_at: Time.current,
        residence_verified_at: Time.current
      )

      user.valid?

      # We ignore password complexity errors for YS users, but keep other validations
      other_errors = user.errors.messages.except(:password)

      if other_errors.empty?
        if user.save(validate: false)
          user.errors.clear
          return user
        end
      else
        Rails.logger.error("Failed to create YS user #{username}: #{other_errors}")
      end

      nil
    end

  def self.validate_document_number(document_number)
    return false if document_number.blank?

    DOCUMENT_ID_STRATEGIES.any? do |strategy|
      if strategy.is_a?(Regexp)
        # Check against Regex
        document_number.to_s.match?(strategy)
      elsif strategy.is_a?(Symbol) && respond_to?(strategy)
        # Call the custom method
        send(strategy, document_number)
      end
    end
  end

    def self.valid_ys_document?(document_number)
      return false unless document_number.to_s.length == 16

      prefix = document_number.to_s[0, 6]
      middle = document_number.to_s[6, 8]
      suffix = document_number.to_s[14, 2]

      # 1. Check if the prefix exists in our known mapping
      council_name = NEC_PREFIX_MAPPING[prefix]
      return false unless council_name # Reject immediately if prefix is unknown

      # 2. Check if the corresponding Geozone actually exists in the database
      expected_geozone = "ys_#{council_name}"
      return false unless Geozone.exists?(name: expected_geozone)

      # 3. Perform the standard YS digit structure checks
      # The middle must be exactly 8 digits.
      # The suffix (issue number) must specifically be between 01 and 05.
      return false unless middle.match?(/\A\d{8}\z/) && suffix.match?(/\A0[1-5]\z/)

      true
    end

  def self.valid_na_document?(document_number)
    # Define the allowed formats
    allowed_formats = [
      /\AON0\d{4,14}\z/, # NA digital
      /\A[Pp]0\d{5,9}[a-zA-Z0-9]\z/ # NA Library cards
    ]

    # Check if the document number matches ANY of the formats
    allowed_formats.any? { |regex| document_number.to_s.match?(regex) }
  end
end
