# app/components/custom/admin/dashboard/index_component.rb
class Admin::Dashboard::IndexComponent < ApplicationComponent; end

load Rails.root.join("app", "components", "admin", "dashboard", "index_component.rb")
class Admin::Dashboard::IndexComponent < ApplicationComponent

  attr_reader :consul_version_info, :local_version_info, :latest_changes

  def initialize
    # --- Consul Version ---
    @consul_version_info = get_version_info("CHANGELOG.md")

    # --- Local Version & Changes ---
    @local_version_info = get_version_info("CHANGELOG-LOCAL.md", is_local: true)
    @latest_changes = extract_latest_changes("CHANGELOG-LOCAL.md")
    @branch = get_branch_info
  end

  private
  def get_branch_info
    revisions_log_path = Rails.root.join("..", "..", "revisions.log")

    unless File.exist?(revisions_log_path)
      Rails.logger.warn "[BranchInfo] revisions.log not found at #{revisions_log_path}"
      return { text: "Deployment information not available.", error: true }
    end

    begin
      # Read all lines, reverse them, and find the first one that matches a deployment.
      # This correctly finds the last deployment even if a rollback happened after.
      last_deploy_line = File.readlines(revisions_log_path).reverse.find do |line|
        line.start_with?("Branch")
      end

      if last_deploy_line
        regex = /^Branch\s+(?<branch>\S+)\s+\(at\s+(?<hash>\w+)\)/
        match = last_deploy_line.match(regex)

        if match
          return {
            branch: match[:branch],
            hash: match[:hash][0, 7], # Get short hash
            error: false
          }
        end
      end

      # If no matching line is found
      Rails.logger.info "[BranchInfo] No valid deployment line found in revisions.log."
      { text: "Could not determine deployment branch.", error: true }

    rescue StandardError => e
      Rails.logger.error "[BranchInfo] Error reading revisions.log: #{e.class.name} - #{e.message}"
      { text: "Error reading deployment info.", error: true }
    end
  end

  def get_version_info(filename, is_local: false)
    match = extract_latest_version_from_changelog(filename)
    if match.is_a?(MatchData)
      url = is_local ? match[:url].sub("/tree/", "/releases/tag/v") : match[:url].sub("/tree/", "/releases/tag/")
      {
        text: "Version #{match[:version]} (#{match[:date]})",
        url: url,
        error: false
      }
    else
      { text: match, url: nil, error: true } # match is an error string here
    end
  end

  def extract_latest_version_from_changelog(filename)
    changelog_path = Rails.root.join(filename)
    return "Changelog file not found." unless File.exist?(changelog_path)

    begin
      File.open(changelog_path, 'r') do |file|
        file.each_line.lazy.first(20).each do |line|
          cleaned_line = line.sub(/^\xEF\xBB\xBF/, '').strip
          regex = /^##\s+\[(?<version>[^\]]+)\]\((?<url>[^)]+)\)\s+\((?<date>\d{4}-\d{2}-\d{2})\)/
          match = cleaned_line.match(regex)
          return match if match
        end
      end
      Rails.logger.info "[ChangelogExtractor] Version not found in first 20 lines of #{filename}."
      "Latest version information not found in the expected format."
    rescue StandardError => e
      Rails.logger.error "[ChangelogExtractor] Error reading #{filename}: #{e.class.name} - #{e.message}"
      "Error extracting version."
    end
  end

  def extract_latest_changes(filename)
    changelog_path = Rails.root.join(filename)
    unless File.exist?(changelog_path)
      Rails.logger.warn "[ChangelogExtractor] Changelog file not found for latest changes: #{changelog_path}"
      return {}
    end

    changes = { "Added" => [], "Changed" => [], "Fixed" => [] }
    capturing = false
    current_section = nil

    begin
      File.foreach(changelog_path) do |line|
        cleaned_line = line.sub(/^\xEF\xBB\xBF/, "").strip

        # A version header marks the start/end of a section of changes
        if cleaned_line.start_with?("## [")
          break if capturing # We found the *next* version, so we stop.
          capturing = true   # This is the first version, so we start.
          next
        end

        next unless capturing

        # Check for a section change (### Added, etc.)
        if cleaned_line.start_with?("### ")
          section_match = cleaned_line.match(/^###\s+(Added|Changed|Fixed)/)
          current_section = section_match ? section_match[1] : nil
          next
        end

        # Capture list items under the current section
        if current_section && cleaned_line.start_with?("-", "*")
          # More robustly strip prefixes like "- **Fix:** ", "- ", or "* "
          item_text = cleaned_line.sub(/^[-*]\s*(\*\*.*?\*\*[:\s]*)?/, "").strip
          changes[current_section] << item_text unless item_text.empty?
        end
      end


      final_changes = changes.reject { |_, v| v.empty? }
      Rails.logger.info "[ChangelogExtractor] Extracted changes: #{final_changes.inspect}"
      final_changes

    rescue StandardError => e
      Rails.logger.error "[ChangelogExtractor] Error extracting latest changes: #{e.class.name} - #{e.message}"
      {} # Return empty hash on error
    end
  end

  def support_link
    mail_to "consul@cosla.gov.uk"
  end

  def documentation_link
    link_to "https://docs.consuldemocracy.org", "https://docs.consuldemocracy.org", target: "_blank"
  end
end
