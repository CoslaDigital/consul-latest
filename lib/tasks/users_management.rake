require 'csv'

namespace :users do

  def self.switch_tenant(subdomain)
    clean_subdomain = subdomain.to_s.gsub(/['"]/, '').strip

    if clean_subdomain.blank? || clean_subdomain == 'public'
      puts "No tenant specified. Running in 'public' schema."
      Apartment::Tenant.switch!("public")
      yield("public")
    else
      tenant = Tenant.find_by(schema: clean_subdomain)
      if tenant.nil?
        puts "❌ Error: Tenant '#{clean_subdomain}' not found in the database."
        exit
      end
      puts "🏢 Switching to tenant database schema: #{tenant.schema}..."
      Apartment::Tenant.switch(tenant.schema) do
        yield(tenant.schema)
      end
    end
  end

  # =========================================================================
  # TASK 1: MULTI-TENANT USER GENERATION (DATE & INDEX RANGE IN FILENAME)
  # =========================================================================
  desc 'Generate batch users inside a specific tenant or public schema with date and sequence range filenames'
  task :generate, [:tenant_subdomain, :prefix, :number, :geozone_name, :password_type] => :environment do |_task, args|

    self.switch_tenant(args[:tenant_subdomain]) do |active_schema|
      username_prefix = (args[:prefix] || 'demo').to_s.gsub(/['"]/, '').strip
      num_users = (args[:number] || 6).to_i
      geozone_name = args[:geozone_name].to_s.gsub(/['"]/, '').strip
      password_type = (args[:password_type] || 'complex').to_s.gsub(/['"]/, '').strip
      year_suffix = Time.current.year % 100

      geozone = geozone_name.present? ? Geozone.find_or_create_by(name: geozone_name) : nil
      geozone_id = geozone&.id
      geozone_text = geozone&.name || 'Nil'

      # Word Pools
      verbs = %w[jump run walk fly swim read write sing draw code talk cook bake play rest ride drive push pull lift skip hop leap grow glow find seek]
      places = %w[london paris madrid berlin tokyo austin boston denver dublin rome vienna lisbon prague miami milan cairo seoul sydney munich athens]
      creatures = %w[badger beagle cat camel dog dolphin eagle elephant fox ferret giraffe hawk jaguar koala lemur lion otter panda puma rabbit tiger wolf zebra]
      child_friendly_nouns = %w[cat dog bat rat cow fox hen pig ant bee owl eel ram ape bug fly toy sun fan hat cap box bag car bus van pen pot cup lid bed mat pan leg arm toe]

      four_letter_words = verbs.select { |w| w.length == 4 }
      places_sanitized = places.map { |w| w.downcase.gsub(/[^a-z]/, '') }
      medium_friendly_words = creatures.select { |w| w.length.between?(4, 8) }

      # Calculate indices to establish filename range
      existing_count = User.where("username LIKE ?", "#{username_prefix}#{year_suffix}%").count
      start_index = existing_count + 1
      end_index = existing_count + num_users

      # Assemble descriptive filename: date + sequence index bounds
      date_stamp = Time.current.strftime('%Y-%m-%d')
      output_file_path = "#{active_schema}_#{username_prefix}_usernames_#{date_stamp}_range_#{start_index}_to_#{end_index}.csv"

      puts "🚀 Starting generation for #{num_users} users..."
      puts "📂 Output file isolated to: #{output_file_path}"
      puts "--------------------------------------------------------"

      CSV.open(output_file_path, "w") do |csv|
        User.transaction do
          num_users.times do |i|
            current_index = existing_count + i + 1
            username = "#{username_prefix}#{year_suffix}#{current_index}"

            password = case password_type
                       when 'simple'
                         "#{child_friendly_nouns.sample}.#{rand(1000..9999)}"
                       when 'medium'
                         "#{medium_friendly_words.sample}.#{rand(1000..9999)}"
                       else
                         "#{places_sanitized.sample}.#{four_letter_words.sample}#{rand(100..999)}"
                       end

            begin
              user = User.create!(
                username: username,
                email: nil,
                password: password,
                password_confirmation: password,
                confirmed_at: Time.current,
                verified_at: Time.current,
                residence_verified_at: Time.current,
                terms_of_service: '1',
                geozone_id: geozone_id
              )

              puts "✅ [#{active_schema}] Created -> Username: #{user.username.ljust(15)} | Geozone: #{geozone_text}"
              csv << [user.username, password, geozone_text]

            rescue ActiveRecord::RecordInvalid => e
              puts "❌ Error creating user '#{username}': #{e.message}"
            end
          end
        end
      end
      puts "--------------------------------------------------------"
      puts "🎉 Generation complete for '#{active_schema}'!"
      puts "📄 Final credentials file for distribution: #{output_file_path}"
    end
  end

  # =========================================================================
  # TASK 2: MULTI-TENANT USER ERASURE
  # =========================================================================
  desc 'Interactively erase and anonymize active users inside a targeted geozone and tenant schema'
  task :erase_by_geozone, [:tenant_subdomain] => :environment do |_task, args|

    self.switch_tenant(args[:tenant_subdomain]) do |active_schema|
      print "Enter the exact Geozone name to wipe inside the '#{active_schema}' schema: "
      STDOUT.flush
      geozone_name = STDIN.gets.chomp.strip

      geozone = Geozone.find_by("name ILIKE ?", geozone_name)

      if geozone.nil?
        puts "❌ Geozone '#{geozone_name}' not found within tenant '#{active_schema}'."
        exit
      end

      users_to_erase = User.active.where(geozone_id: geozone.id)
      user_count = users_to_erase.count

      puts "\n========================================================"
      puts "🏢 Current Tenant: #{active_schema}"
      puts "📍 Target Geozone: #{geozone.name} (ID: #{geozone.id})"
      puts "👥 Found #{user_count} active users eligible for erasure."
      puts "========================================================"

      if user_count.zero?
        puts "No active users found matching this criteria. Exiting."
        exit
      end

      puts "\n🚀 Starting DRY RUN simulation..."
      puts "--------------------------------------------------------"

      ActiveRecord::Base.transaction do
        users_to_erase.find_each do |user|
          puts "Simulating erasure -> ID: #{user.id.to_s.ljust(6)} | Username: #{(user.username || 'No Username').ljust(20)} | Email: #{user.email}"
          user.erase("Mass geozone cleanup simulation")
        end
        puts "\n🔄 Simulation complete. Tearing down temporary changes..."
        raise ActiveRecord::Rollback
      end

      puts "🏁 Database state rolled back safely. No production changes occurred."
      puts "--------------------------------------------------------"

      puts "\n⚠️  WARNING: Proceeding will PERMANENTLY remove PII data for these #{user_count} users inside schema '#{active_schema}'."
      print "Type 'CONFIRM ERASE' to commit these changes permanently, or anything else to abort: "
      STDOUT.flush
      live_confirmation = STDIN.gets.chomp.strip

      if live_confirmation == "CONFIRM ERASE"
        puts "\n💥 Executing live data erasure..."

        ActiveRecord::Base.transaction do
          users_to_erase.find_each do |user|
            user.erase("Mass cleanup: Geozone #{geozone.name} lifecycle removal")
            puts "✅ Erased User ID: #{user.id}"
          end
        end
        puts "\n🎉 Success! #{user_count} users successfully scrubbed from tenant '#{active_schema}'."
      else
        puts "\n❌ Process safely aborted. No production adjustments made."
      end
    end
  end
end
