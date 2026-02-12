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
    @logger = Logger.new(Rails.root.join("log", "ml.log"))
    @logger.info "[MachineLearning] Job started for #{job.script} at #{Time.current}"
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
    questions = Legislation::Question.all
    questions = questions.limit(DRY_RUN_LIMIT) if dry_run

    questions.find_each do |question|
      comments = question.comments.where(hidden_at: nil).pluck(:body)
      next if comments.empty?

      context = "Process: #{question.process.title}\nQuestion: #{question.title}"
      result = MlHelper.summarize_comments(comments, context, config: ml_config)
      next if result.blank?

      sentiment_data = process_sentiment_data(result["sentiment"])

      if dry_run
        Rails.logger.info "[DryRun] Leg. Summary for ID #{question.id}: #{result['summary_markdown'].truncate(100)}"
      else
        summary = MlSummaryComment.find_or_initialize_by(commentable: question)
        summary.update!(
          body: result["summary_markdown"],
          sentiment_analysis: sentiment_data
        )
      end
    end
  end

  def generate_budget_related_content
    process_related_content_for(Budget::Investment, MachineLearning.investments_related_filename)
  end

  def generate_proposal_related_content
    process_related_content_for(Proposal, MachineLearning.proposals_related_filename)
  end

  # --- CLASS METHODS (ADMIN UI SUPPORT) ---

  class << self
    def enabled?
      Setting["feature.machine_learning"].present?
    end

    def llm_configured?
      Setting['feature.machine_learning'] &&
        Setting['llm.provider'].present? &&
        Setting['llm.model'].present?
    end

    def script_kinds
      %w[tags related_content comments_summary]
    end

    def scripts_info
      AVAILABLE_SCRIPTS.keys.map do |key|
        {
          key: key,
          description: I18n.t("admin.machine_learning.scripts.#{key}.description")
        }
      end
    end

    def script_select_options
      AVAILABLE_SCRIPTS.keys.map do |key|
        [I18n.t("admin.machine_learning.scripts.#{key}.label"), key]
      end
    end

    def data_folder
      Rails.root.join("public", Tenant.path_with_subfolder("machine_learning/data"))
    end

    def data_path(filename)
      "/#{Tenant.path_with_subfolder("machine_learning/data")}/#{filename}"
    end

    def data_output_files
      files = { tags: [], related_content: [], comments_summary: [] }
      [
        [proposals_tags_filename, :tags],
        [investments_tags_filename, :tags],
        [debates_tags_filename, :tags],
        [proposals_related_filename, :related_content],
        [investments_related_filename, :related_content],
        [proposals_comments_summary_filename, :comments_summary],
        [investments_comments_summary_filename, :comments_summary]
      ].each do |filename, kind|
        files[kind] << filename if File.exist?(data_folder.join(filename))
      end
      files
    end

    def data_intermediate_files
      excluded = [
        "proposals.json", "budget_investments.json", "comments.json",
        proposals_tags_filename, proposals_taggings_filename,
        investments_tags_filename, investments_taggings_filename,
        debates_tags_filename, debates_taggings_filename,
        proposals_related_filename, investments_related_filename,
        proposals_comments_summary_filename, investments_comments_summary_filename
      ]
      json_files = Dir[data_folder.join("*.json")].map { |f| File.basename(f) }
      csv_files = Dir[data_folder.join("*.csv")].map { |f| File.basename(f) }
      (json_files + csv_files - excluded).sort
    end

    # Filename Constants
    def proposals_tags_filename; "ml_tags_proposals.json"; end
    def proposals_taggings_filename; "ml_taggings_proposals.json"; end
    def debates_tags_filename; "ml_tags_debates.json"; end
    def debates_taggings_filename; "ml_taggings_debates.json"; end
    def investments_tags_filename; "ml_tags_budgets.json"; end
    def investments_taggings_filename; "ml_taggings_budgets.json"; end
    def proposals_related_filename; "ml_related_content_proposals.json"; end
    def investments_related_filename; "ml_related_content_budgets.json"; end
    def proposals_comments_summary_filename; "ml_comments_summaries_proposals.json"; end
    def investments_comments_summary_filename; "ml_comments_summaries_budgets.json"; end
  end

  private

  def ml_config
    @ml_config ||= {
      enabled: Setting['feature.machine_learning'],
      provider: Setting['llm.provider'],
      model: Setting['llm.model'],
      max_tokens: Setting['llm.max_tokens']
    }.freeze
  end

  def process_sentiment_data(raw_sentiment)
    # Default structure
    default_val = { "positive" => 0, "negative" => 0, "neutral" => 100 }
    return default_val if raw_sentiment.blank?

    if raw_sentiment.is_a?(Hash)
      # Ensure keys are strings and values are integers
      pos = raw_sentiment["positive"].to_i
      neg = raw_sentiment["negative"].to_i
      neu = raw_sentiment["neutral"].to_i

      # Math Insurance: Force the sum to 100%
      total = pos + neg + neu
      if total != 100 && total > 0
        neu = 100 - (pos + neg)
      end

      { "positive" => pos, "negative" => neg, "neutral" => [neu, 0].max }
    else
      # Case where LLM returns a string: "positive"
      label = raw_sentiment.to_s.downcase.strip
      case label
      when "positive" then { "positive" => 100, "negative" => 0, "neutral" => 0 }
      when "negative" then { "positive" => 0, "negative" => 100, "neutral" => 0 }
      else default_val
      end
    end
  end

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
          tag_name: clean_name.downcase, taggable_id: id,
          taggable_type: type, context: 'ml_tags', created_at: Time.current
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

    # Identify records with comments
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
          # Standardize the sentiment using our private helper method
          sentiment_data = process_sentiment_data(result["sentiment"])

          if dry_run
            Rails.logger.info "[DryRun] Summary for ID #{id}: #{result['summary_markdown'].truncate(100)}"
            Rails.logger.info "[DryRun] Sentiment for ID #{id}: #{sentiment_data.inspect}"
          else
            summary = MlSummaryComment.find_or_initialize_by(commentable: record)
            summary.update!(
              body: result["summary_markdown"],
              sentiment_analysis: sentiment_data # Verified variable name
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

  # --- DB HELPERS ---

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
        tag_id: real_id, taggable_id: data[:taggable_id],
        taggable_type: data[:taggable_type], context: data[:context], created_at: data[:created_at]
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

  # --- UTILITIES ---

  def should_generate_summary_for?(record)
    last_summary = MlSummaryComment.where(commentable: record).order(created_at: :desc).first
    return true if last_summary.blank? || last_summary.sentiment_analysis.blank?
    latest_comment = record.comments.where(hidden_at: nil).maximum(:updated_at)
    latest_comment ? latest_comment > last_summary.updated_at : false
  end

  def log_progress(task_type, current, total, item_id)
    msg = "[MachineLearning] #{task_type}: #{current}/#{total} - ID: #{item_id}"
    Rails.logger.info msg
    puts msg
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

  def set_previous_modified_date
    {
      MachineLearning.investments_tags_filename => last_modified_date_for(MachineLearning.investments_tags_filename),
      MachineLearning.proposals_tags_filename => last_modified_date_for(MachineLearning.proposals_tags_filename),
      MachineLearning.debates_tags_filename => last_modified_date_for(MachineLearning.debates_tags_filename)
    }
  end

  def last_modified_date_for(filename)
    path = MachineLearning.data_folder.join(filename)
    File.exist?(path) ? File.mtime(path) : nil
  end
end
