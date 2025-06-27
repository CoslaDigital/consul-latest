class Admin::Dashboard::IndexComponent < ApplicationComponent; end

load Rails.root.join("app", "components", "admin", "dashboard", "index_component.rb")
class Admin::Dashboard::IndexComponent < ApplicationComponent
  attr_reader :consul_version

  def initialize
    @consul_version = extract_latest_version_from_changelog("CHANGELOG.md")
    # Assuming your local changelog is named 'CHANGELOG-local.md'. Change if necessary.
    @local_version  = extract_latest_version_from_changelog("CHANGELOG-LOCAL.md")
  end
  
  private

  def extract_latest_version_from_changelog(filename)
    changelog_path = Rails.root.join(filename)

    unless File.exist?(changelog_path)
      Rails.logger.warn "[ChangelogExtractor] Changelog file not found at: #{changelog_path}"
      return "Changelog file not found."
    end

    begin
      File.open(changelog_path, 'r') do |file|
        file.each_line.with_index do |line, index|
          break if index >= 20

          cleaned_line = line.sub(/^\xEF\xBB\xBF/, '').strip

          # The Regex:
          # ^##\s+                  => Starts with "##" and one or more spaces
          # \[(?<version>[^\]]+)\]  => Captures version inside "[...]" (e.g., "2.3.1")
          # \([^)]+\)               => Matches the URL part "(...)" (we don't capture this)
          # \s+                     => One or more spaces
          # \((?<date>\d{4}-\d{2}-\d{2})\) => Captures date inside "(YYYY-MM-DD)"
          regex = /^##\s+\[(?<version>[^\]]+)\]\([^)]+\)\s+\((?<date>\d{4}-\d{2}-\d{2})\)/
          match = cleaned_line.match(regex)

          if match
          # Successfully found and parsed the line
            return "Version #{match[:version]} (#{match[:date]})"
          end
        end
      end

      # If the loop completes, it means no matching line was found in the first N lines
      Rails.logger.info "[ChangelogExtractor] Latest version line not found in the expected format within the first 20 lines of #{changelog_path}."
      return "Latest version information not found in the expected format."

      rescue StandardError => e
      # Log the error class, message, and backtrace for detailed debugging
      Rails.logger.error "[ChangelogExtractor] Error reading or parsing changelog: #{e.class.name} - #{e.message}"
      Rails.logger.error "[ChangelogExtractor] Backtrace:\n#{e.backtrace.join("\n")}"
      return "Error extracting version." # Generic message to the UI
      end
    end


    def support_link
      mail_to "consul@cosla.gov.uk"
    end

    def documentation_link
      link_to "https://docs.consuldemocracy.org", "https://docs.consuldemocracy.org"
    end

end
