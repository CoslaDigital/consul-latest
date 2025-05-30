class Admin::Dashboard::IndexComponent < ApplicationComponent; end

load Rails.root.join("app", "components", "admin", "dashboard", "index_component.rb")
class Admin::Dashboard::IndexComponent < ApplicationComponent
attr_reader :consul_version

  def initialize
    @consul_version = extract_latest_version_from_changelog
    @revision = read_production_revisions_log
  end

  private

def read_production_revisions_log
  # 1. Rails.root points to something like /path/to/consul/releases/YYYYMMDDHHMMSS/
  #    (because 'current' is a symlink to a release directory)
  current_release_path = Rails.root

  # 2. current_release_path.parent will be /path/to/consul/releases/
  releases_directory_path = current_release_path.parent

  # 3. releases_directory_path.parent will be /path/to/consul/
  consul_base_path = releases_directory_path.parent # This is your 'consul' directory

  # 4. Construct the full path to the revisions.log file within the 'consul' directory
  revisions_log_path = consul_base_path.join('revisions.log')

  # 5. Check if the file exists and read it
  if File.exist?(revisions_log_path)
    begin
    last_line = File.readlines(revisions_log_path).last&.strip

      if last_line.nil? || last_line.empty?
        Rails.logger.info "[RevisionsLogReader] revisions.log at #{revisions_log_path} is empty or the last line is blank."
        return "Revisions log is empty or last line is blank."
      else
        return last_line
      end
    rescue StandardError => e
      Rails.logger.error "[RevisionsLogReader] Error reading production revisions.log at #{revisions_log_path}: #{e.message}"
      Rails.logger.error "[RevisionsLogReader] Backtrace:\n#{e.backtrace.join("\n")}"
      return "Error reading revisions.log."
    end
  else
    Rails.logger.warn "[RevisionsLogReader] Production revisions.log not found at: #{revisions_log_path}"
    return "revisions.log not found."
  end
end

def extract_latest_version_from_changelog
  changelog_path = Rails.root.join('CHANGELOG.md')

  unless File.exist?(changelog_path)
    Rails.logger.warn "[ChangelogExtractor] Changelog file not found at: #{changelog_path}"
    return "Changelog file not found."
  end

  begin
    File.open(changelog_path, 'r') do |file|
      file.each_line.with_index do |line, index|
        # Optimization: Only check the first, say, 20 lines. Adjust if your version line can be further down.
        break if index >= 20

        # Remove potential Byte Order Mark (BOM) and leading/trailing whitespace from the line
        # The BOM can sometimes cause issues with regex matching at the start of a file/line.
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
