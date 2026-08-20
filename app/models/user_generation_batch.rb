require 'csv'

class UserGenerationBatch < ApplicationRecord
  belongs_to :admin_user, class_name: "User"
  has_one_attached :credentials_file

  def process_generation!(prefix, geozone_id, password_type)
    successful_rows = []

    year_suffix = Time.current.year % 100
    existing_count = User.where("username LIKE ?", "#{prefix}#{year_suffix}%").count

    self.target_count.times do |i|
      current_index = existing_count + i + 1
      username = "#{prefix}#{year_suffix}#{current_index}"
      password = generate_password(password_type)

      user = User.new(
        username: username,
        email: nil,
        password: password,
        password_confirmation: password,
        terms_of_service: '1',
        confirmed_at: Time.current,
        verified_at: Time.current,
        residence_verified_at: Time.current,
        geozone_id: geozone_id,
        newsletter: false,
        email_digest: false,
        email_on_direct_message: false,
        email_on_comment: false,
        email_on_comment_reply: false
      )

      if user.save
        successful_rows << [user.username, password]
        increment!(:success_count)
      end
    end

    # Build the CSV and attach it securely
    csv_data = CSV.generate(headers: true) do |csv|
      csv << ["Username", "Password"]
      successful_rows.each { |row| csv << row }
    end

    credentials_file.attach(
      io: StringIO.new(csv_data),
      filename: "batch_#{self.id}_#{prefix}_credentials.csv",
      content_type: "text/csv"
    )

    update!(status: "completed")
  end

  private

    def generate_password(type)
      verbs = %w[jump run walk fly swim read write sing draw code talk cook bake play rest ride drive push pull lift skip hop leap grow glow find seek]
      places = %w[london paris madrid berlin tokyo austin boston denver dublin rome vienna lisbon prague miami milan cairo seoul sydney munich athens]
      creatures = %w[badger beagle cat camel dog dolphin eagle elephant fox ferret giraffe hawk jaguar koala lemur lion otter panda puma rabbit tiger wolf zebra]
      child_friendly_nouns = %w[cat dog bat rat cow fox hen pig ant bee owl eel ram ape bug fly toy sun fan hat cap box bag car bus van pen pot cup lid bed mat pan leg arm toe]

      four_letter_words = verbs.select { |w| w.length == 4 }
      medium_friendly_words = creatures.select { |w| w.length.between?(4, 8) }

      case type.to_s.downcase
      when 'simple'
        "#{child_friendly_nouns.sample}.#{rand(1000..9999)}"
      when 'medium'
        "#{medium_friendly_words.sample}.#{rand(1000..9999)}"
      else
        "#{places.sample}.#{four_letter_words.sample}#{rand(100..999)}"
      end
    end
end
