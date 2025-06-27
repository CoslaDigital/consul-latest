class Admin::Dashboard::IndexComponent < ApplicationComponent; end

load Rails.root.join("app", "components", "admin", "dashboard", "index_component.rb")
class Admin::Dashboard::IndexComponent < ApplicationComponent
  attr_reader :consul_version

  def initialize
    consul_match = extract_latest_version_from_changelog("CHANGELOG.md")
    if consul_match.is_a?(MatchData)
      # On success, build a hash with the text, the URL, and no error
      @consul_version_info = {
        text: "Version #{consul_match[:version]} (#{consul_match[:date]})",
        url: consul_match[:url].sub('/tree/', '/releases/tag/'),
        error: false
      }
    else
      # On failure, build a hash with the error message
      @consul_version_info = { text: consul_match, url: nil, error: true }
    end
 
    local_match = extract_latest_version_from_changelog("CHANGELOG-LOCAL.md")
    if local_match.is_a?(MatchData)
      @local_version_info = {
        text: "Version #{local_match[:version]} (#{local_match[:date]})",
        url: local_match[:url].sub('/tree/', '/releases/tag/v'),
        error: false
      }
    else
      @local_version_info = { text: local_match, url: nil, error: true }
    end
 
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

          regex = /^##\s+\[(?<version>[^\]]+)\]\((?<url>[^)]+)\)\s+\((?<date>\d{4}-\d{2}-\d{2})\)/
          match = cleaned_line.match(regex)

          return match if match
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
