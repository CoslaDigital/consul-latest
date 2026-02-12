# app/models/machine_learning.rb
class MachineLearning
  attr_reader :user, :script, :previous_modified_date, :dry_run
  attr_accessor :job

  DRY_RUN_LIMIT = 5 # Number of items to process during a dry run
  SCRIPTS_FOLDER = Rails.root.join("public", "machine_learning", "scripts").freeze

  AVAILABLE_SCRIPTS = {
    "budget_comments"       => :generate_budget_comments_summary,
    "proposal_comments"     => :generate_proposal_comments_summary,
    "legislation_summaries" => :generate_legislation_question_summaries,
    "budget_tags"           => :generate_budget_tags,
    "debate_tags"           => :generate_debate_tags,
    "proposal_tags"         => :generate_proposal_tags,
    "budget_related"        => :generate_budget_related_content,
    "proposal_related"      => :generate_proposal_related_content
  }.freeze

  def initialize(job, dry_run: false)
    @job = job
    @user = job.user
    @dry_run = dry_run
    @previous_modified_date = set_previous_modified_date
  end

  def run
    Rails.logger.info "[MachineLearning] RUNNING IN DRY RUN MODE" if dry_run

    unless ml_config[:enabled]
      job.update!(error: "Machine learning feature is not enabled", finished_at: Time.current)
      Mailer.machine_learning_error(user).deliver_later
      return false
    end

    unless ml_config[:provider].present?
      job.update!(error: "LLM provider not configured", finished_at: Time.current)
      Mailer.machine_learning_error(user).deliver_later
      return false
    end

    method_name = AVAILABLE_SCRIPTS[job.script]

    if method_name.present?
      send(method_name)
    else
      fail_job("Unknown script: #{job.script}")
      return false
    end

    unless dry_run
      job.update!(finished_at: Time.current)
      Mailer.machine_learning_success(user).deliver_later
    end

    true
  rescue StandardError => e
    handle_error(e)
  end

  # --- TASK METHODS ---

  def generate_budget_tags
    process_tags_for(scope: Budget::Investment.joins(:translations), type: 'Budget::Investment', log_name: "budget tags")
  end

  def generate_proposal_tags
    process_tags_for(scope: Proposal.joins(:translations), type: 'Proposal', log_name: "proposal tags")
  end

  def generate_debate_tags
    process_tags_for(scope: Debate.all, type: 'Debate', log_name: "debate tags")
  end

  def generate_budget_comments_summary
    process_comments_summary_for(Budget::Investment, "budget comments", "Budget Investment")
  end

  def generate_proposal_comments_summary
    process_comments_summary_for(Proposal, "proposal comments", "Proposal")
  end

  def generate_legislation_question_summaries
    # This method iterates internally; we apply the limit directly here
    questions = Legislation::Question.all
    questions = questions.limit(DRY_RUN_LIMIT) if dry_run

    questions.find_each do |question|
      comments = question.comments.where(hidden_at: nil).pluck(:body)
      next if comments.empty?

      context = "Process: #{question.process.title}\nQuestion: #{question.title}"
      result = MlHelper.summarize_comments(comments, context, config: ml_config)
      next if result.blank?

      if dry_run
        Rails.logger.info "[DryRun] Leg. Summary for ID #{question.id}: #{result['summary_markdown'].truncate(100)}"
      else
        summary = MlSummaryComment.find_or_initialize_by(commentable: question)
        summary.update!(body: result["summary_markdown"], sentiment_analysis: result["sentiment"])
      end
    end
  end

  def generate_budget_related_content
    process_related_content_for(Budget::Investment, MachineLearning.investments_related_filename)
  end

  def generate_proposal_related_content
    process_related_content_for(Proposal, MachineLearning.proposals_related_filename)
  end

  # --- CLASS METHODS ---

  class << self
    def enabled?
      Setting["feature.machine_learning"].present?
    end

    def data_folder
      Rails.root.join("public", Tenant.path_with_subfolder("machine_learning/data"))
    end

    def llm_configured?
      Setting['feature.machine_learning'] && Setting['llm.provider'].present? && Setting['llm.model'].present?
    end

    def investments_related_filename; "ml_related_content_budgets.json"; end
    def proposals_related_filename; "ml_related_content_proposals.json"; end
  end

  private

  # --- HYBRID MEMOIZATION ---

  def ml_config
    @ml_config ||= {
      enabled: Setting['feature.machine_learning'],
      provider: Setting['llm.provider'],
      model: Setting['llm.model'],
      max_tokens: Setting['llm.max_tokens']
    }.freeze
  end

  # --- SHARED PROCESSING LOGIC ---

  def process_tags_for(scope:, type:, log_name:)
    Rails.logger.info "[MachineLearning] Starting #{log_name} generation"
    cleanup_tags_for!(type) unless dry_run

    all_taggings_data = []
    all_tags_to_ensure = Set.new

    records = scope.pluck(:id, :title, :description)
    records = records.take(DRY_RUN_LIMIT) if dry_run

    total = records.count
    processed = 0

    records.each do |id, title, description|
      text = "#{title}\n\n#{description}"
      generated_names = MlHelper.generate_tags(text, 5, config: ml_config)

      Rails.logger.info "[DryRun] Tags for ID #{id}: #{generated_names.join(', ')}" if dry_run

      generated_names.each do |tag_name|
        clean_name = tag_name.strip.truncate(150)
        next if clean_name.blank?

        all_tags_to_ensure << clean_name
        all_taggings_data << {
          tag_name: clean_name.downcase,
          taggable_id: id,
          taggable_type: type,
          context: 'ml_tags',
          created_at: Time.current
        }
      end
      processed += 1
      log_progress(log_name, processed, total, id)
    end

    unless dry_run
      bulk_sync_tags_and_taggings(all_tags_to_ensure, all_taggings_data)
      update_machine_learning_info_for("tags")
    end
  end

  def process_comments_summary_for(klass, log_name, context_prefix)
    Rails.logger.info "[MachineLearning] Starting #{log_name}"
    cleanup_comments_summary_for!(klass.name) unless dry_run

    ids = klass.joins(:comments).where(comments: { hidden_at: nil }).group("#{klass.table_name}.id").pluck(:id)
    ids = ids.take(DRY_RUN_LIMIT) if dry_run

    total = ids.count
    processed = 0

    ids.each do |id|
      record = klass.find(id)
      next unless should_generate_summary_for?(record)

      comments = record.comments.where("length(body) > 10").order(:created_at).pluck(:body).uniq
      if comments.any?
        result = MlHelper.summarize_comments(comments, "#{context_prefix}: #{record.title}", config: ml_config)
        if result&.[]("summary_markdown").present?
          Rails.logger.info "[DryRun] Summary for ID #{id}: #{result['summary_markdown'].truncate(100)}" if dry_run

          unless dry_run
            MlSummaryComment.find_or_initialize_by(commentable: record).update!(
              body: result["summary_markdown"],
              sentiment_analysis: result["sentiment"]
            )
          end
        end
      end
      processed += 1
      log_progress(log_name, processed, total, id)
    end
    update_machine_learning_info_for("comments_summary") unless dry_run
  end

  def process_related_content_for(klass, filename)
    cleanup_related_content_for!(klass.name) unless dry_run
    all_content = klass.joins(:translations).pluck(:id, :title, :description).map { |id, t, d| { id: id, text: "#{t} #{d}" } }

    loop_content = dry_run ? all_content.take(DRY_RUN_LIMIT) : all_content
    results = []
    total = loop_content.count

    loop_content.each_with_index do |item, idx|
      candidates = all_content.reject { |c| c[:id] == item[:id] }
      candidate_texts = candidates.map { |c| c[:text] }
      similar_indices = MlHelper.find_similar_content(item[:text], candidate_texts, 3, config: ml_config)
      related_ids = similar_indices.map { |i| candidates[i][:id] }

      Rails.logger.info "[DryRun] Related for ID #{item[:id]}: #{related_ids.join(', ')}" if dry_run

      res = { id: item[:id] }
      related_ids.each_with_index { |rid, i| res["related_#{i}"] = rid }
      results << res
      log_progress("related content", idx + 1, total, item[:id])
    end

    unless dry_run
      import_related_content_from_array(results, klass.name)
      update_machine_learning_info_for("related_content")
    end
  end

  # --- DATABASE BULK HELPERS ---

  def bulk_sync_tags_and_taggings(tag_names_set, taggings_metadata)
    return if tag_names_set.empty?
    tag_map = {}

    tag_names_set.each do |name|
      clean_name = name.strip.truncate(150)
      begin
        tag = Tag.find_or_create_by!(name: clean_name)
        tag_map[clean_name.downcase] = tag.id
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        tag = Tag.where("LOWER(name) = ?", clean_name.downcase).first
        tag_map[clean_name.downcase] = tag.id if tag
      end
    end

    final_taggings = taggings_metadata.map do |data|
      real_id = tag_map[data[:tag_name]]
      next unless real_id
      {
        tag_id: real_id,
        taggable_id: data[:taggable_id],
        taggable_type: data[:taggable_type],
        context: data[:context],
        created_at: data[:created_at]
      }
    end.compact.uniq { |t| [t[:tag_id], t[:taggable_id], t[:taggable_type], t[:context]] }

    Tagging.insert_all(final_taggings) if final_taggings.any?
  end

  def cleanup_tags_for!(type)
    Tagging.where(context: "ml_tags", taggable_type: type).delete_all
    Tag.where("NOT EXISTS (SELECT 1 FROM taggings WHERE taggings.tag_id = tags.id)").delete_all
  end

  def cleanup_comments_summary_for!(type)
    MlSummaryComment.where(commentable_type: type).delete_all
  end

  def cleanup_related_content_for!(type)
    RelatedContent.where(machine_learning: true, parent_relationable_type: type).delete_all
  end

  # --- UTILITY METHODS ---

  def should_generate_summary_for?(record)
    last_summary = MlSummaryComment.where(commentable: record).order(created_at: :desc).first
    return true if last_summary.blank? || last_summary.sentiment_analysis.blank?

    latest_comment = record.comments.where(hidden_at: nil).maximum(:updated_at)
    latest_comment ? latest_comment > last_summary.updated_at : false
  end

  def log_progress(task_type, current, total, item_id)
    if current % 10 == 0 || current == total
      Rails.logger.info "[MachineLearning] #{task_type}: #{current}/#{total} - ID: #{item_id}"
    end
  end

  def import_related_content_from_array(results, record_type)
    results.each do |result|
      parent_id = result.delete(:id)
      score = result.size
      result.each do |_, child_id|
        next unless child_id.present?
        RelatedContent.create!(
          parent_relationable_id: parent_id, parent_relationable_type: record_type,
          child_relationable_id: child_id, child_relationable_type: record_type,
          machine_learning: true, machine_learning_score: score, author: user
        )
        score -= 1
      end
    end
  end

  def update_machine_learning_info_for(kind)
    MachineLearningInfo.find_or_create_by!(kind: kind).update!(generated_at: job.started_at, script: job.script)
  end

  def handle_error(error)
    message = error.message
    backtrace = error.backtrace.select { |line| line.include?("machine_learning.rb") }.first(3)
    job.update!(finished_at: Time.current, error: ([message] + backtrace).join("<br>"))
    Mailer.machine_learning_error(user).deliver_later
  end

  def fail_job(message)
    job.update!(error: message, finished_at: Time.current)
    Mailer.machine_learning_error(user).deliver_later
  end

  def set_previous_modified_date; {}; end
end
