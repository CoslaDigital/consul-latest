# app/models/legislation/propositions_import.rb
require 'csv'

class Legislation::PropositionsImport
  include ActiveModel::Model

  # Match the exact headers shown in image_a3bef9.png
  ATTRIBUTES = %w[proposition topic opinion r1_quotes approval_rate proposition_id duplicate selected schulze_rank pav_rank rank].freeze
  ALLOWED_FILE_EXTENSIONS = %w[csv].freeze

  attr_accessor :file, :created_process, :created_questions, :invalid_rows

  validates :file, presence: true
  validate :file_extension, if: -> { @file.present? }
  validate :file_headers_definition, if: -> { @file.present? && valid_extension? }

  def initialize(attributes = {})
    if attributes.present?
      attributes.each do |attr, value|
        public_send("#{attr}=", value)
      end
    end
    @created_questions = []
    @invalid_rows = []
  end

  def save(author)
    return false if invalid?

    # --- LOCALE AGNOSTIC REMOVAL ---
    # Removed strict 'I18n.locale =' assignment. The database saves data into
    # whatever language context the current user is active in on the application.

    raw_rows = CSV.read(file.path, headers: true)
    harvested_topic = raw_rows.first ? raw_rows.first['topic'].to_s.strip : "Community"

    # Count only the rows our pipeline selected to give an accurate summary metric
    selected_propositions_count = raw_rows.count { |r| r['selected'].to_s.upcase == "TRUE" }

    # Placeholder text arrays default to UK English spelling standards natively
    dynamic_title = "Citizen Consultation: Focused Review on #{harvested_topic}"
    dynamic_summary = "An automated, data-driven legislative review process containing " \
      "**#{selected_propositions_count} verified policy propositions** extracted from recent public contributions."

    dynamic_description = "### Overarching Theme: #{harvested_topic}\n" \
      "This consultation area presents specific strategic policy adjustments " \
      "generated using natural language processing models from our community listening campaigns. " \
      "Please vote on each proposition below to help establish a collective priority roadmap."

    @created_process = Legislation::Process.new(
      title: dynamic_title,
      summary: dynamic_summary,
      description: dynamic_description,
      start_date: Date.current,
      end_date: Date.current + 30.days,
      published: false,
      draft_start_date: Date.current,
      draft_end_date: Date.current + 30.days,
      draft_phase_enabled: true
    )

    unless @created_process.save
      errors.add(:file, "Could not generate parent legislation process: #{@created_process.errors.full_messages.join(', ')}")
      return false
    end

    raw_rows.each do |row|
      next if empty_row?(row)

      # Skip rows where 'selected' is FALSE
      next unless row['selected'].to_s.upcase == "TRUE"

      process_row(row, author)
    end
    true
  end

  private

    def process_row(row, author)
      question = Legislation::Question.new(
        legislation_process_id: @created_process.id,
        author_id: author.id,
        title: row['proposition'].to_s.strip,
        description: "### Context Tracking\n" \
          "* **Category Group:** #{row['topic']}\n" \
          "* **AI Consensus Score:** #{row['approval_rate']}\n" \
          "* **Pipeline Rank (PAV):** #{row['pav_rank']}"
      )

      if question.invalid?
        @invalid_rows << row.to_hash
      else
        question.save!

        # UK spelling variants for standard placeholder survey choice arrays
        ["In Favour / Agree", "Against / Disagree", "Abstain / Undecided"].each do |label|
          Legislation::QuestionOption.create!(legislation_question_id: question.id, value: label)
        end

        @created_questions << question
      end
    end

    def empty_row?(row)
      row.all? { |_, cell| cell.nil? }
    end

    def file_extension
      return if valid_extension?
      errors.add :file, :extension, valid_extensions: ALLOWED_FILE_EXTENSIONS.join(", ")
    end

    def fetch_file_headers
      CSV.open(file.path, &:readline)
    end

    def file_headers_definition
      headers = fetch_file_headers

      required_keys = %w[proposition topic approval_rate selected]
      return if required_keys.all? { |k| headers.include?(k) }

      errors.add :file, :headers, required_headers: required_keys.join(", ")
    end

    def valid_extension?
      ALLOWED_FILE_EXTENSIONS.include? extension
    end

    def extension
      File.extname(file.original_filename).delete(".")
    end
end
