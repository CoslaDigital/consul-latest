# frozen_string_literal: true

module Sensemaker
  class Job < ApplicationRecord
    self.table_name = "sensemaker_jobs"

    SCRIPTS = Sensemaker::Scripts::SCRIPTS
    PUBLISHABLE_SCRIPTS = Sensemaker::Scripts::PUBLISHABLE_SCRIPTS
    PIPELINE_SCRIPTS = Sensemaker::Scripts::PIPELINE_SCRIPTS

    ANALYSABLE_TYPES = [
      "Debate",
      "Proposal",
      "Poll",
      "Poll::Question",
      "Legislation::Process",
      "Legislation::Question",
      "Legislation::Proposal",
      "Legislation::QuestionOption",
      "Budget",
      "Budget::Group"
    ].freeze

    validates :analysable_type, inclusion: { in: ANALYSABLE_TYPES }
    validates :script, inclusion: { in: SCRIPTS }, allow_nil: true

    belongs_to :user, optional: false
    belongs_to :parent_job, class_name: "Sensemaker::Job", optional: true
    has_many :children, class_name: "Sensemaker::Job", foreign_key: :parent_job_id, inverse_of: :parent_job,
                        dependent: :nullify

    validates :analysable_type, presence: true
    validates :analysable_id, presence: true, unless: -> { analysable_type == "Proposal" }
    validate :publishing_is_allowed

    belongs_to :analysable, polymorphic: true, optional: true

    before_save :set_persisted_output_if_successful
    after_destroy :cleanup_associated_files

    scope :published, -> { where(published: true) }
    scope :unpublished, -> { where(published: false) }

    def started?
      started_at.present?
    end

    def finished?
      finished_at.present?
    end

    def errored?
      error.present?
    end

    def cancelled?
      finished_at.present? && error.eql?("Cancelled")
    end

    def running?
      started? && !finished?
    end

    def status
      if cancelled?
        "Cancelled"
      elsif errored?
        "Failed"
      elsif finished?
        "Completed"
      elsif started?
        "Running"
      else
        "Unstarted"
      end
    end

    def self.unstarted
      where(started_at: nil).where(finished_at: nil)
    end

    def self.running
      where.not(started_at: nil).where(finished_at: nil)
    end

    def self.successful
      where(error: nil).where.not(finished_at: nil)
    end

    def self.failed
      where.not(error: nil).where.not(finished_at: nil)
    end

    def cancel!
      update!(finished_at: Time.current, error: "Cancelled")
    end

    def work_dir
      return nil if id.blank?

      File.join(Sensemaker::Paths.sensemaker_data_folder, work_dir_basename)
    end

    def relative_work_dir
      return nil if id.blank?

      File.join(Sensemaker::Paths.sensemaker_relative_data_folder, work_dir_basename)
    end

    def conversation
      @conversation ||= Sensemaker::Conversation.new(analysable_type, analysable_id)
    end

    def analysable
      return Proposal if analysable_type == "Proposal" && analysable_id.nil?

      super
    end

    def output_file_name
      Sensemaker::Scripts.primary_output_basename(script)
    end

    def primary_artefact_path
      if persisted_output.present?
        persisted_output_path.to_s
      else
        File.join(work_dir, output_file_name)
      end
    end

    def has_multiple_outputs?
      script == "report_text"
    end

    def default_output_path
      primary_artefact_path
    end

    def relative_primary_artefact_path
      File.join(relative_work_dir, output_file_name)
    end

    def relative_output_path
      relative_primary_artefact_path
    end

    def persisted_output_path
      p = read_attribute(:persisted_output)
      return nil if p.blank?

      Rails.root.join(p)
    end

    def output_artefact_paths
      if persisted_output.present?
        base_dir = File.dirname(persisted_output_path.to_s)
        paths = [persisted_output_path.to_s]
      else
        base_dir = work_dir.to_s
        paths = [File.join(base_dir, output_file_name)]
      end
      Sensemaker::Scripts.secondary_output_basenames(script).each do |basename|
        paths << File.join(base_dir, basename)
      end
      paths
    end

    def existing_output_artefact_paths
      output_artefact_paths.select { |path| File.exist?(path) }
    end

    def input_file
      read_attribute(:input_file).presence || default_input_csv
    end

    def input_artefact_paths
      path = read_attribute(:input_file).to_s
      return [] if path.blank?

      [path]
    end

    def existing_input_artefact_paths
      input_artefact_paths.select { |path| File.exist?(path) }
    end

    def has_outputs?
      required_paths = required_output_artefact_paths
      required_paths.all? { |path| File.exist?(path) }
    end

    def publishable?
      finished? && !errored? && PUBLISHABLE_SCRIPTS.include?(script) && has_outputs?
    end

    def default_input_csv
      return nil if work_dir.blank?

      File.join(work_dir, "input.csv")
    end

    def categorize_output_csv
      return nil if work_dir.blank?

      File.join(work_dir, Sensemaker::Scripts.primary_output_basename("categorize"))
    end

    def bridge_scores_csv
      return nil if work_dir.blank?

      File.join(work_dir, Sensemaker::Scripts.primary_output_basename("bridge_scores"))
    end

    def world_model_pkl
      return nil if work_dir.blank?

      File.join(work_dir, Sensemaker::Scripts.primary_output_basename("propositions"))
    end

    def refined_world_model_pkl
      return nil if work_dir.blank?

      File.join(work_dir, Sensemaker::Scripts.primary_output_basename("refine_propositions"))
    end

    def self.budget_related
      where(analysable_type: "Budget").or(
        where(analysable_type: "Budget::Group")
      )
    end

    def self.for_budget_any_status(budget)
      group_subquery = budget.groups.select(:id)
      where(analysable_type: "Budget", analysable_id: budget.id).or(
        where(analysable_type: "Budget::Group", analysable_id: group_subquery)
      )
    end

    def self.for_budget(budget)
      published.merge(for_budget_any_status(budget))
    end

    def self.process_related
      where(analysable_type: "Legislation::Process").or(
        where(analysable_type: "Legislation::Proposal").or(
          where(analysable_type: "Legislation::Question").or(
            where(analysable_type: "Legislation::QuestionOption")
          )
        )
      )
    end

    def self.for_process_any_status(process)
      proposals_subquery = process.proposals.select(:id)
      questions_subquery = process.questions.select(:id)
      question_options_subquery = Legislation::QuestionOption
                                  .where(legislation_question_id: questions_subquery)
                                  .select(:id)

      where(analysable_type: "Legislation::Proposal", analysable_id: proposals_subquery)
        .or(where(analysable_type: "Legislation::Question", analysable_id: questions_subquery))
        .or(where(analysable_type: "Legislation::QuestionOption",
                  analysable_id: question_options_subquery))
    end

    def self.for_process(process)
      published.merge(for_process_any_status(process))
    end

    def self.poll_related
      where(analysable_type: "Poll").or(
        where(analysable_type: "Poll::Question")
      )
    end

    def self.for_poll_any_status(poll)
      questions_subquery = poll.questions.select(:id)
      where(analysable_type: "Poll", analysable_id: poll.id).or(
        where(analysable_type: "Poll::Question", analysable_id: questions_subquery)
      )
    end

    def self.for_poll(poll)
      published.merge(for_poll_any_status(poll))
    end

    def self.legislation_question_related
      where(analysable_type: "Legislation::Question").or(
        where(analysable_type: "Legislation::QuestionOption")
      )
    end

    def self.for_legislation_question_any_status(question)
      options_subquery = question.question_options.select(:id)
      where(analysable_type: "Legislation::Question", analysable_id: question.id).or(
        where(analysable_type: "Legislation::QuestionOption", analysable_id: options_subquery)
      )
    end

    def self.for_legislation_question(question)
      published.merge(for_legislation_question_any_status(question))
    end

    def self.for_analysable(record, published_only: true)
      if record == Proposal
        base = where(analysable_type: "Proposal", analysable_id: nil)
        return published_only ? base.merge(published) : base
      end

      case record
      when Budget
        published_only ? for_budget(record) : for_budget_any_status(record)
      when Legislation::Process
        published_only ? for_process(record) : for_process_any_status(record)
      when Poll
        published_only ? for_poll(record) : for_poll_any_status(record)
      when Legislation::Question
        published_only ? for_legislation_question(record) : for_legislation_question_any_status(record)
      else
        base = where(analysable: record)
        published_only ? base.merge(published) : base
      end
    end

    def self.by_analysable_type(type)
      case type
      when "Budget"
        budget_related
      when "Legislation::Process"
        process_related
      when "Poll"
        poll_related
      when "Legislation::Question"
        legislation_question_related
      else
        where(analysable_type: type)
      end
    end

    private

      def work_dir_basename
        "job-#{id}"
      end

      def required_output_artefact_paths
        [primary_artefact_path]
      end

      def publishing_is_allowed
        return unless published? && published_changed? && !published_was

        unless publishable?
          errors.add(:published, :not_publishable, message: "cannot be published")
        end
      end

      def set_persisted_output_if_successful
        return if id.blank?
        return unless finished_at.present? && error.nil?
        return if persisted_output.present?

        if has_outputs?
          self.persisted_output = relative_primary_artefact_path
        end
      end

      def cleanup_associated_files
        result = []
        result << cleanup_work_dir
        result << cleanup_persisted_output
        result.flatten!
        result.compact!
        Rails.logger.info("Cleaned up files for job #{id}: #{result.inspect}")
        result
      rescue => e
        Rails.logger.warn("Failed to cleanup files for job #{id}: #{e.message}")
        nil
      end

      def cleanup_work_dir
        dir = work_dir
        return [] if dir.blank? || !File.directory?(dir)

        [FileUtils.rm_rf(dir)]
      end

      def cleanup_persisted_output
        path = persisted_output_path
        return [] unless path.present? && File.exist?(path)

        [FileUtils.rm_f(path)]
      end
  end
end
