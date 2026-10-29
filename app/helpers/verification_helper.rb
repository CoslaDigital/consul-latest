module VerificationHelper
  def document_types
    [[t("verification.residence.new.document_type.spanish_id"), 1],
     [t("verification.residence.new.document_type.passport"), 2],
     [t("verification.residence.new.document_type.residence_card"), 3]]
  end

  def mask_phone(number)
    match = number.match(/\d{3}$/)
    "******#{match}"
  end

  def mask_email(string)
    match = string.match(/^(\w{1,3})(.*)@(.*)/)

    data_to_display = match[1]
    data_to_mask    = match[2]
    email_provider  = match[3]

    "#{data_to_display}#{"*" * data_to_mask.size}@#{email_provider}"
  end

  def self.postal_code_allowed_by_settings?(postcode_to_check)
    return true if Setting["postal_codes"].blank?

    # Normalize the user's input right away (e.g. "FK10 2FB" -> "fk102fb")
    normalized_input = postcode_to_check.to_s.strip.gsub(/\s+/, '').downcase

    Setting["postal_codes"].split(",").any? do |code_or_range|
      code_or_range = code_or_range.strip.gsub(/\s+/, '').downcase

      if code_or_range.include?(":")
        # It's a range (e.g. "ab101aa:ab129zz")
        range_start, range_end = code_or_range.split(":")
        (range_start..range_end).cover?(normalized_input)
      else
        # It's an exact or partial match (allows "fk10" to match "FK10 2FB")
        normalized_input.start_with?(code_or_range)
      end
    end
  end
end
