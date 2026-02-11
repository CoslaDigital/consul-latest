# app/models/machine_learning.rb
class MachineLearning
  attr_reader :user, :script, :previous_modified_date
  attr_accessor :job

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
  def initialize(job)
    @job = job
    @user = job.user
    @previous_modified_date = set_previous_modified_date
  end

  def run
    # Check if ML is enabled
    unless Setting['feature.machine_learning']
      job.update!(error: "Machine learning feature is not enabled", finished_at: Time.current)
      Mailer.machine_learning_error(user).deliver_later
      return false
    end

    # Check if LLM is configured
    unless Setting['llm.provider'].present?
      job.update!(error: "LLM provider not configured in settings", finished_at: Time.current)
      Mailer.machine_learning_error(user).deliver_later
      return false
    end


    # 2. Look up the method in our configuration
    method_name = AVAILABLE_SCRIPTS[job.script]

    # 3. Execute the mapped method
    if method_name.present?
      send(method_name)
    else
      # Fallback for legacy jobs or unknown scripts
      fail_job("Unknown script: #{job.script}")
      return false
    end

    job.update!(finished_at: Time.current)
    Mailer.machine_learning_success(user).deliver_later
    true
  rescue Exception => e
    handle_error(e)
  end

  # Budget Comments Summary (replaces budgets_summary_comments_textrank.py)
  def generate_budget_comments_summary

    Rails.logger.info "[MachineLearning] Starting budget comments summarization"

    # Clean up existing summaries
    cleanup_investments_comments_summary!

    results = []

    # FIXED: Use group instead of distinct to avoid PostgreSQL error
    investment_ids = Budget::Investment.joins(:comments)
                                       .where(comments: { hidden_at: nil })
                                       .group('budget_investments.id')
                                       .pluck(:id)

    total = investment_ids.count
    processed = 0

    investment_ids.each_slice(10) do |batch_ids|
      Budget::Investment.where(id: batch_ids).each do |investment|
        next unless should_generate_summary_for?(investment)

        # Simple query that works
        comments = investment.comments
                             .order(:created_at)
                             .select { |c| c.body.present? && c.body.length > 10 }
                             .map(&:body)
                             .uniq

        if comments.any?
          context = "Budget Investment: #{investment.title}"

          # CHANGED: 'result' is now a Hash { "summary_markdown" => "...", "sentiment" => {...} }
          result = generate_comments_summary(comments, context)

          if result.present? && result["summary_markdown"].present?
            summary_text = result["summary_markdown"]
            sentiment_data = result["sentiment"]

            # Save to database
            ml_summary = MlSummaryComment.find_or_initialize_by(
              commentable_id: investment.id,
              commentable_type: 'Budget::Investment'
            )
            ml_summary.body = summary_text
            ml_summary.sentiment_analysis = sentiment_data # <--- Added Sentiment
            ml_summary.save!

            # Add to results for file export
            results << {
              id: results.size,
              commentable_id: investment.id,
              commentable_type: 'Budget::Investment',
              body: summary_text # <--- Save only the text part to the CSV/JSON file
            }
          end
        end

        processed += 1
        log_progress("budget comments", processed, total, investment.id)
      end
    end

    # Save results to files (for compatibility)
    save_comments_summary_results(results, MachineLearning.investments_comments_summary_filename)

    update_machine_learning_info_for("comments_summary")

    Rails.logger.info "[MachineLearning] Completed budget comments summarization. Processed #{processed} investments."
  end

  # Proposal Comments Summary (replaces proposals_summary_comments_textrank.py)
  def generate_proposal_comments_summary
    Rails.logger.info "[MachineLearning] Starting proposal comments summarization"
    cleanup_proposals_comments_summary!

    results = []

    # FIXED: Changed from .distinct to .group('proposals.id') to fix PG::InvalidColumnReference
    proposal_ids = Proposal.joins(:comments)
                           .where(comments: { hidden_at: nil })
                           .group('proposals.id')
                           .pluck(:id)

    total = proposal_ids.count
    processed = 0

    proposal_ids.each_slice(10) do |batch_ids|
      Proposal.where(id: batch_ids).each do |proposal|
        next unless should_generate_summary_for?(proposal)

        # FIXED: Filter length in Ruby to avoid "column body does not exist" error
        # FIXED: Use map/uniq in Ruby to avoid "SELECT DISTINCT" ordering error
        comments = proposal.comments
                           .order(:created_at)
                           .select { |c| c.body.present? && c.body.length > 10 }
                           .map(&:body)
                           .uniq

        if comments.any?
          context = "Proposal: #{proposal.title}"

          # CHANGED: 'result' is now a Hash { "summary_markdown" => "...", "sentiment" => {...} }
          result = generate_comments_summary(comments, context)

          if result.present? && result["summary_markdown"].present?
            summary_text = result["summary_markdown"]
            sentiment_data = result["sentiment"]

            ml_summary = MlSummaryComment.find_or_initialize_by(
              commentable_id: proposal.id,
              commentable_type: 'Proposal'
            )
            ml_summary.body = summary_text
            ml_summary.sentiment_analysis = sentiment_data # <--- Added Sentiment
            ml_summary.save!

            results << {
              id: results.size,
              commentable_id: proposal.id,
              commentable_type: 'Proposal',
              body: summary_text # <--- Save only the text part to the CSV/JSON file
            }
          end
        end

        processed += 1
        log_progress("proposal comments", processed, total, proposal.id)
      end
    end

    save_comments_summary_results(results, MachineLearning.proposals_comments_summary_filename)
    update_machine_learning_info_for("comments_summary")
    Rails.logger.info "[MachineLearning] Completed proposal comments summarization. Processed #{processed} proposals."
  end

  # Budget Tags
  def generate_budget_tags
    # REMOVED: The check for Setting['machine_learning.tags'] so data generates regardless of display setting.
    Rails.logger.info "[MachineLearning] Starting budget tags generation"

    cleanup_investments_tags!

    tags = []
    taggings = []

    # OPTIMIZATION: Eager load translations
    investments = Budget::Investment.includes(:translations)
    total = investments.count
    processed = 0

    investments.find_each(batch_size: 5) do |investment|
      text = "#{investment.title}\n\n#{investment.description}"
      generated_tags = generate_tags_from_text(text, 5)

      generated_tags.each do |tag_name|
        tag = find_or_create_tag(tags, tag_name)

        taggings << {
          tag_id: tag[:id],
          taggable_id: investment.id,
          taggable_type: 'Budget::Investment',
          context: 'ml_tags',
          created_at: Time.current.iso8601
        }
      end

      processed += 1
      log_progress("budget tags", processed, total, investment.id)
    end

    save_tags_results(tags, taggings,
                      MachineLearning.investments_tags_filename,
                      MachineLearning.investments_taggings_filename)

    import_tags_from_arrays(tags, taggings, 'Budget::Investment')
    update_machine_learning_info_for("tags")

    Rails.logger.info "[MachineLearning] Completed budget tags generation. Processed #{processed} investments."
  end

  def generate_legislation_question_summaries
    # Iterate over all questions
    Legislation::Question.find_each do |question|

      # 1. Get the comments
      # We pluck the body directly to save memory
      comments = question.comments.where(hidden_at: nil).pluck(:body)

      # Skip if there's nothing to summarize
      next if comments.empty?

      # 2. Build the Context manually
      # This gives the LLM the "meta" info it needs to understand the debate
      context_parts = []
      context_parts << "Process: #{question.process.title}"
      context_parts << "Question: #{question.title}"

      if question.question_options.any?
        options_list = question.question_options.pluck(:value).join(', ')
        context_parts << "Available Options: #{options_list}"
      end

      context_string = context_parts.join("\n")

      # 3. Call the LLM Helper
      result = MlHelper.summarize_comments(comments, context_string)
      next if result.blank?

      summary_body = result["summary_markdown"]
      sentiment_data = result["sentiment"]

      # 4. Save the Summary
      # We use the polymorphic association to save it safely
      summary = MlSummaryComment.find_or_initialize_by(
        commentable: question
      )
      summary.body = summary_body
      summary.sentiment_analysis = sentiment_data
      summary.save!

      Rails.logger.info "[MachineLearning] Saved summary for Legislation::Question #{question.id}"
    end
  rescue => e
    Rails.logger.error "[MachineLearning] Error in generate_legislation_question_summaries: #{e.message}"
  end

  # Proposal Tags
  def generate_proposal_tags
    # REMOVED: The check for Setting['machine_learning.tags']
    Rails.logger.info "[MachineLearning] Starting proposal tags generation"

    cleanup_proposals_tags!

    tags = []
    taggings = []

    # OPTIMIZATION: Eager load translations
    proposals = Proposal.includes(:translations)
    total = proposals.count
    processed = 0

    proposals.find_each(batch_size: 5) do |proposal|
      text = "#{proposal.title}\n\n#{proposal.description}"
      generated_tags = generate_tags_from_text(text, 5)

      generated_tags.each do |tag_name|
        tag = find_or_create_tag(tags, tag_name)

        taggings << {
          tag_id: tag[:id],
          taggable_id: proposal.id,
          taggable_type: 'Proposal',
          context: 'ml_tags',
          created_at: Time.current.iso8601
        }
      end

      processed += 1
      log_progress("proposal tags", processed, total, proposal.id)
    end

    save_tags_results(tags, taggings,
                      MachineLearning.proposals_tags_filename,
                      MachineLearning.proposals_taggings_filename)

    import_tags_from_arrays(tags, taggings, 'Proposal')
    update_machine_learning_info_for("tags")

    Rails.logger.info "[MachineLearning] Completed proposal tags generation. Processed #{processed} proposals."
  end

  # Debate Tags
  def generate_debate_tags
    Rails.logger.info "[MachineLearning] Starting debate tags generation"

    cleanup_debate_tags!

    tags = []
    taggings = []

    # OPTIMIZATION: Eager load translations if Debate supports Globalize, otherwise just use find_each
    # debates = Debate.includes(:translations)
    debates = Debate.all
    total = debates.count
    processed = 0

    debates.find_each(batch_size: 5) do |debate|
      # Combine Title and Description for the LLM
      text = "#{debate.title}\n\n#{debate.description}"

      # Generate 5 tags
      generated_tags = generate_tags_from_text(text, 5)

      generated_tags.each do |tag_name|
        tag = find_or_create_tag(tags, tag_name)

        taggings << {
          tag_id: tag[:id],
          taggable_id: debate.id,
          taggable_type: 'Debate', # <--- Critical change
          context: 'ml_tags',
          created_at: Time.current.iso8601
        }
      end

      processed += 1
      log_progress("debate tags", processed, total, debate.id)
    end

    # Save to JSON files
    save_tags_results(tags, taggings,
                      MachineLearning.debates_tags_filename,
                      MachineLearning.debates_taggings_filename)

    # Import to Database
    import_tags_from_arrays(tags, taggings, 'Debate')
    update_machine_learning_info_for("tags")

    Rails.logger.info "[MachineLearning] Completed debate tags generation. Processed #{processed} debates."
  end

  # Budget Related Content
  def generate_budget_related_content
    # REMOVED: The check for Setting['machine_learning.related_content']
    Rails.logger.info "[MachineLearning] Starting budget related content generation"

    cleanup_investments_related_content!

    results = []

    # OPTIMIZATION: Pre-calculate all texts ONCE.
    all_content_map = Budget::Investment.includes(:translations).map do |inv|
      { id: inv.id, text: "#{inv.title} #{inv.description}" }
    end

    total = all_content_map.count
    processed = 0

    all_content_map.each do |item|
      source_text = item[:text]

      candidates = all_content_map.reject { |c| c[:id] == item[:id] }
      candidate_texts = candidates.map { |c| c[:text] }

      similar_indices = find_similar_content(source_text, candidate_texts, 3)
      related_ids = similar_indices.map { |idx| candidates[idx][:id] }

      results << {
        id: item[:id]
      }.tap do |hash|
        related_ids.each_with_index do |related_id, idx|
          hash["related_#{idx}"] = related_id
        end
      end

      processed += 1
      log_progress("budget related content", processed, total, item[:id])
    end

    save_related_content_results(results, MachineLearning.investments_related_filename)
    import_related_content_from_array(results, 'Budget::Investment')
    update_machine_learning_info_for("related_content")

    Rails.logger.info "[MachineLearning] Completed budget related content generation. Processed #{processed} investments."
  end

  # Proposal Related Content
  def generate_proposal_related_content
    # REMOVED: The check for Setting['machine_learning.related_content']
    Rails.logger.info "[MachineLearning] Starting proposal related content generation"

    cleanup_proposals_related_content!

    results = []

    # OPTIMIZATION: Pre-calculate all texts ONCE.
    all_content_map = Proposal.includes(:translations).map do |p|
      { id: p.id, text: "#{p.title} #{p.description}" }
    end

    total = all_content_map.count
    processed = 0

    all_content_map.each do |item|
      source_text = item[:text]

      candidates = all_content_map.reject { |c| c[:id] == item[:id] }
      candidate_texts = candidates.map { |c| c[:text] }

      similar_indices = find_similar_content(source_text, candidate_texts, 3)
      related_ids = similar_indices.map { |idx| candidates[idx][:id] }

      results << {
        id: item[:id]
      }.tap do |hash|
        related_ids.each_with_index do |related_id, idx|
          hash["related_#{idx}"] = related_id
        end
      end

      processed += 1
      log_progress("proposal related content", processed, total, item[:id])
    end

    save_related_content_results(results, MachineLearning.proposals_related_filename)
    import_related_content_from_array(results, 'Proposal')
    update_machine_learning_info_for("related_content")

    Rails.logger.info "[MachineLearning] Completed proposal related content generation. Processed #{processed} proposals."
  end

  class << self
    def enabled?
      Setting["feature.machine_learning"].present?
    end

    def proposals_filename
      "proposals.json"
    end

    def investments_filename
      "budget_investments.json"
    end

    def comments_filename
      "comments.json"
    end

    def data_folder
      Rails.root.join("public", tenant_data_folder)
    end

    def tenant_data_folder
      Tenant.path_with_subfolder("machine_learning/data")
    end

    def data_output_files
      files = { tags: [], related_content: [], comments_summary: [] }

      if File.exist?(data_folder.join(proposals_tags_filename))
        files[:tags] << proposals_tags_filename
      end
      if File.exist?(data_folder.join(proposals_taggings_filename))
        files[:tags] << proposals_taggings_filename
      end
      if File.exist?(data_folder.join(investments_tags_filename))
        files[:tags] << investments_tags_filename
      end
      if File.exist?(data_folder.join(investments_taggings_filename))
        files[:tags] << investments_taggings_filename
      end
      if File.exist?(data_folder.join(debates_tags_filename))
        files[:tags] << debates_tags_filename
      end
      if File.exist?(data_folder.join(debates_taggings_filename))
        files[:tags] << debates_taggings_filename
      end
      if File.exist?(data_folder.join(proposals_related_filename))
        files[:related_content] << proposals_related_filename
      end
      if File.exist?(data_folder.join(investments_related_filename))
        files[:related_content] << investments_related_filename
      end

      if File.exist?(data_folder.join(proposals_comments_summary_filename))
        files[:comments_summary] << proposals_comments_summary_filename
      end
      if File.exist?(data_folder.join(investments_comments_summary_filename))
        files[:comments_summary] << investments_comments_summary_filename
      end

      files
    end

    def data_intermediate_files
      excluded = [
        proposals_filename,
        investments_filename,
        comments_filename,
        proposals_tags_filename,
        proposals_taggings_filename,
        investments_tags_filename,
        investments_taggings_filename,
        proposals_related_filename,
        investments_related_filename,
        proposals_comments_summary_filename,
        investments_comments_summary_filename
      ]
      json = Dir[data_folder.join("*.json")].map do |full_path_filename|
        full_path_filename.split("/").last
      end
      csv = Dir[data_folder.join("*.csv")].map do |full_path_filename|
        full_path_filename.split("/").last
      end
      (json + csv - excluded).sort
    end

    def proposals_tags_filename
      "ml_tags_proposals.json"
    end

    def proposals_taggings_filename
      "ml_taggings_proposals.json"
    end

    def debates_tags_filename
      "ml_tags_debates.json"
    end

    def debates_taggings_filename
      "ml_taggings_debates.json"
    end

    def investments_tags_filename
      "ml_tags_budgets.json"
    end

    def investments_taggings_filename
      "ml_taggings_budgets.json"
    end

    def proposals_related_filename
      "ml_related_content_proposals.json"
    end

    def investments_related_filename
      "ml_related_content_budgets.json"
    end

    def proposals_comments_summary_filename
      "ml_comments_summaries_proposals.json"
    end

    def investments_comments_summary_filename
      "ml_comments_summaries_budgets.json"
    end

    def data_path(filename)
      "/#{tenant_data_folder}/#{filename}"
    end

    def script_kinds
      %w[tags related_content comments_summary]
    end

    def scripts_info
      AVAILABLE_SCRIPTS.keys.map do |key|
        {
          key: key, # Used for HTML ID matching
          description: I18n.t("admin.machine_learning.scripts.#{key}.description")
        }
      end
      Dir[SCRIPTS_FOLDER.join("*.py")].map do |full_path_filename|
        {
          name: full_path_filename.split("/").last,
          description: description_from(full_path_filename)
        }
      end.sort_by { |script_info| script_info[:name] }
    end

    def script_select_options
      AVAILABLE_SCRIPTS.keys.map do |key|
        [I18n.t("admin.machine_learning.scripts.#{key}.label"), key]
      end
    end

    def description_from(script_filename)
      description = ""
      delimiter = '"""'
      break_line = "<br>"
      comment_found = false
      File.readlines(script_filename).each do |line|
        if line.start_with?(delimiter) && !comment_found
          comment_found = true
          line.slice!(delimiter)
          description << line.strip.concat(break_line) if line.present?
        elsif line.include?(delimiter)
          line.slice!(delimiter)
          description << line.strip if line.present?
          break
        elsif comment_found
          description << line.strip.concat(break_line)
        end
      end

      description.delete_suffix(break_line)
    end

    def llm_configured?
      Setting['feature.machine_learning'] &&
        Setting['llm.provider'].present? &&
        Setting['llm.model'].present?
    end
  end

  private

  # Core ML methods that use your existing LLM configuration
  def generate_comments_summary(comments, context = nil)
    MlHelper.summarize_comments(comments, context)
  end

  def generate_tags_from_text(text, max_tags = 5)
    MlHelper.generate_tags(text, max_tags)
  end

  def find_similar_content(source_text, candidate_texts, max_results = 3)
    MlHelper.find_similar_content(source_text, candidate_texts, max_results)
  end

  def llm_configured?
    self.class.llm_configured?
  end

  # Helper methods

  def should_generate_summary_for?(record)
    # 1. Fetch the existing summary
    last_summary = MlSummaryComment.where(
      commentable_id: record.id,
      commentable_type: record.class.name
    ).order(created_at: :desc).first

    # Case A: No summary exists? -> GENERATE
    return true if last_summary.blank?

    # Case B: Summary exists, but has no sentiment? -> REGENERATE
    return true if last_summary.sentiment_analysis.blank? || last_summary.sentiment_analysis == {}

    # Case C: Summary is perfect, but are there new comments? -> REGENERATE
    latest_comment = record.comments.where(hidden_at: nil).maximum(:updated_at)

    # If there are no visible comments, we don't need to do anything
    return false unless latest_comment

    # Only return true if the comments are newer than the summary
    latest_comment > last_summary.updated_at
  end

  def log_progress(task_type, current, total, item_id)
    if current % 10 == 0 || current == total
      Rails.logger.info "[MachineLearning] #{task_type}: #{current}/#{total} - ID: #{item_id}"
    end
  end

  def find_or_create_tag(tags_array, tag_name)
    tag_name = tag_name.truncate(150)

    existing_tag = tags_array.find { |t| t[:name] == tag_name }
    return existing_tag if existing_tag

    new_tag = {
      id: tags_array.size + 1,
      name: tag_name,
      taggings_count: 1,
      created_at: Time.current.iso8601
    }

    tags_array << new_tag
    new_tag
  end

  # File export methods (for compatibility with existing system)
  def save_comments_summary_results(results, filename)
    data_folder = MachineLearning.data_folder
    FileUtils.mkdir_p(data_folder)

    # Save JSON
    json_file = data_folder.join(filename)
    File.write(json_file, results.to_json)

    # Save CSV for compatibility
    csv_filename = filename.sub('.json', '.csv')
    csv_file = data_folder.join(csv_filename)

    if results.any?
      CSV.open(csv_file, 'w') do |csv|
        csv << ['id', 'commentable_id', 'commentable_type', 'body']
        results.each do |result|
          csv << [result[:id], result[:commentable_id], result[:commentable_type], result[:body]]
        end
      end
    end
  end

  def save_tags_results(tags, taggings, tags_filename, taggings_filename)
    data_folder = MachineLearning.data_folder
    FileUtils.mkdir_p(data_folder)

    # Save tags JSON
    tags_file = data_folder.join(tags_filename)
    File.write(tags_file, tags.to_json)

    # Save taggings JSON
    taggings_file = data_folder.join(taggings_filename)
    File.write(taggings_file, taggings.to_json)
  end

  def save_related_content_results(results, filename)
    data_folder = MachineLearning.data_folder
    FileUtils.mkdir_p(data_folder)

    json_file = data_folder.join(filename)
    File.write(json_file, results.to_json)
  end

  # Database import methods
  def import_tags_from_arrays(tags, taggings, taggable_type)
    ids = {}

    # 1. Import Tags Safely
    tags.each do |tag_attrs|
      clean_name = tag_attrs[:name].to_s.strip.truncate(150)
      next if clean_name.blank?

      # A. Try to find strictly or case-insensitively first
      tag = Tag.where("LOWER(name) = ?", clean_name.downcase).first

      # B. If not found, try to create it
      unless tag
        begin
          tag = Tag.create!(name: clean_name)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
          # C. If creation fails (race condition or validation), fetch the existing one again
          tag = Tag.where("LOWER(name) = ?", clean_name.downcase).first
        end
      end

      # Map the temp ID (from ML) to the real DB ID
      ids[tag_attrs[:id]] = tag.id if tag
    end

    # 2. Import Taggings Safely
    taggings.each do |tagging_attrs|
      real_tag_id = ids[tagging_attrs[:tag_id]]
      next unless real_tag_id

      # Use find_or_create_by to prevent "Tagging already exists" errors
      begin
        Tagging.find_or_create_by!(
          tag_id: real_tag_id,
          taggable_id: tagging_attrs[:taggable_id],
          taggable_type: taggable_type,
          context: 'ml_tags'
        )
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        # If the tagging exists, just move on
        next
      end
    end
  end

  def import_related_content_from_array(results, record_type)
    results.each do |result|
      id = result.delete(:id)
      score = result.size

      result.each do |_, related_id|
        next unless related_id.present?

        attributes = {
          parent_relationable_id: id,
          parent_relationable_type: record_type,
          child_relationable_id: related_id,
          child_relationable_type: record_type
        }

        related_content = RelatedContent.find_by(attributes)
        if related_content.present?
          related_content.update!(machine_learning_score: score)
        else
          RelatedContent.create!(attributes.merge(
            machine_learning: true,
            author: user,
            machine_learning_score: score
          ))
        end

        score -= 1
      end
    end
  end

  # ORIGINAL METHODS - Keep these exactly as they were

  def create_data_folder
    FileUtils.mkdir_p MachineLearning.data_folder
  end

  def export_proposals_to_json
    create_data_folder
    filename = MachineLearning.data_folder.join(MachineLearning.proposals_filename)
    Proposal::Exporter.new.to_json_file(filename)
  end

  def export_budget_investments_to_json
    create_data_folder
    filename = MachineLearning.data_folder.join(MachineLearning.investments_filename)
    Budget::Investment::Exporter.new(Array.new).to_json_file(filename)
  end

  def export_comments_to_json
    create_data_folder
    filename = MachineLearning.data_folder.join(MachineLearning.comments_filename)
    Comment::Exporter.new.to_json_file(filename)
  end

  def run_machine_learning_scripts
    command = if Tenant.default?
                "python #{job.script}"
              else
                "CONSUL_TENANT=#{Tenant.current_schema} python #{job.script}"
              end

    output = `cd #{SCRIPTS_FOLDER} && #{command} 2>&1`
    result = $?.success?
    if result == false
      job.update!(finished_at: Time.current, error: output)
      Mailer.machine_learning_error(user).deliver_later
    end
    result
  end

  def cleanup_debate_tags!
    Tagging.where(context: "ml_tags", taggable_type: "Debate").find_each(&:destroy!)
    Tag.find_each { |tag| tag.destroy! if Tagging.where(tag: tag).empty? }
  end

  def cleanup_proposals_tags!
    Tagging.where(context: "ml_tags", taggable_type: "Proposal").find_each(&:destroy!)
    Tag.find_each { |tag| tag.destroy! if Tagging.where(tag: tag).empty? }
  end

  def cleanup_investments_tags!
    Tagging.where(context: "ml_tags", taggable_type: "Budget::Investment").find_each(&:destroy!)
    Tag.find_each { |tag| tag.destroy! if Tagging.where(tag: tag).empty? }
  end

  def cleanup_proposals_related_content!
    RelatedContent.with_hidden.for_proposals.from_machine_learning.find_each(&:really_destroy!)
  end

  def cleanup_investments_related_content!
    RelatedContent.with_hidden.for_investments.from_machine_learning.find_each(&:really_destroy!)
  end

  def cleanup_proposals_comments_summary!
    MlSummaryComment.where(commentable_type: "Proposal").find_each(&:destroy!)
  end

  def cleanup_investments_comments_summary!
    MlSummaryComment.where(commentable_type: "Budget::Investment").find_each(&:destroy!)
  end

  def import_ml_proposals_comments_summary
    json_file = MachineLearning.data_folder.join(MachineLearning.proposals_comments_summary_filename)
    json_data = JSON.parse(File.read(json_file)).each(&:deep_symbolize_keys!)
    json_data.each do |attributes|
      attributes.delete(:id)
      unless MlSummaryComment.find_by(commentable_id: attributes[:commentable_id],
                                      commentable_type: "Proposal")
        MlSummaryComment.create!(attributes)
      end
    end
  end

  def import_ml_investments_comments_summary
    json_file = MachineLearning.data_folder.join(MachineLearning.investments_comments_summary_filename)
    json_data = JSON.parse(File.read(json_file)).each(&:deep_symbolize_keys!)
    json_data.each do |attributes|
      attributes.delete(:id)
      unless MlSummaryComment.find_by(commentable_id: attributes[:commentable_id],
                                      commentable_type: "Budget::Investment")
        MlSummaryComment.create!(attributes)
      end
    end
  end

  def import_proposals_related_content
    json_file = MachineLearning.data_folder.join(MachineLearning.proposals_related_filename)
    json_data = JSON.parse(File.read(json_file)).each(&:deep_symbolize_keys!)
    json_data.each do |related|
      id = related.delete(:id)
      score = related.size
      related.each do |_, related_id|
        if related_id.present?
          attributes = {
            parent_relationable_id: id,
            parent_relationable_type: "Proposal",
            child_relationable_id: related_id,
            child_relationable_type: "Proposal"
          }
          related_content = RelatedContent.find_by(attributes)
          if related_content.present?
            related_content.update!(machine_learning_score: score)
          else
            RelatedContent.create!(attributes.merge(machine_learning: true,
                                                    author: user,
                                                    machine_learning_score: score))
          end
        end
        score -= 1
      end
    end
  end

  def import_budget_investments_related_content
    json_file = MachineLearning.data_folder.join(MachineLearning.investments_related_filename)
    json_data = JSON.parse(File.read(json_file)).each(&:deep_symbolize_keys!)
    json_data.each do |related|
      id = related.delete(:id)
      score = related.size
      related.each do |_, related_id|
        if related_id.present?
          attributes = {
            parent_relationable_id: id,
            parent_relationable_type: "Budget::Investment",
            child_relationable_id: related_id,
            child_relationable_type: "Budget::Investment"
          }
          related_content = RelatedContent.find_by(attributes)
          if related_content.present?
            related_content.update!(machine_learning_score: score)
          else
            RelatedContent.create!(attributes.merge(machine_learning: true,
                                                    author: user,
                                                    machine_learning_score: score))
          end
        end
        score -= 1
      end
    end
  end

  def import_ml_proposals_tags
    ids = {}
    json_file = MachineLearning.data_folder.join(MachineLearning.proposals_tags_filename)
    json_data = JSON.parse(File.read(json_file)).each(&:deep_symbolize_keys!)
    json_data.each do |attributes|
      if attributes[:name].present?
        attributes.delete(:taggings_count)
        if attributes[:name].length >= 150
          attributes[:name] = attributes[:name].truncate(150)
        end
        tag = Tag.find_or_create_by!(name: attributes[:name])
        ids[attributes[:id]] = tag.id
      end
    end

    json_file = MachineLearning.data_folder.join(MachineLearning.proposals_taggings_filename)
    json_data = JSON.parse(File.read(json_file)).each(&:deep_symbolize_keys!)
    json_data.each do |attributes|
      if attributes[:tag_id].present?
        tag_id = ids[attributes[:tag_id]]
        if Tag.find_by(id: tag_id) && attributes[:taggable_id].present?
          attributes[:tag_id] = tag_id
          attributes[:taggable_type] = "Proposal"
          attributes[:context] = "ml_tags"
          Tagging.create!(attributes)
        end
      end
    end
  end

  def import_ml_investments_tags
    ids = {}
    json_file = MachineLearning.data_folder.join(MachineLearning.investments_tags_filename)
    json_data = JSON.parse(File.read(json_file)).each(&:deep_symbolize_keys!)
    json_data.each do |attributes|
      if attributes[:name].present?
        attributes.delete(:taggings_count)
        if attributes[:name].length >= 150
          attributes[:name] = attributes[:name].truncate(150)
        end
        tag = Tag.find_or_create_by!(name: attributes[:name])
        ids[attributes[:id]] = tag.id
      end
    end

    json_file = MachineLearning.data_folder.join(MachineLearning.investments_taggings_filename)
    json_data = JSON.parse(File.read(json_file)).each(&:deep_symbolize_keys!)
    json_data.each do |attributes|
      if attributes[:tag_id].present?
        tag_id = ids[attributes[:tag_id]]
        if Tag.find_by(id: tag_id) && attributes[:taggable_id].present?
          attributes[:tag_id] = tag_id
          attributes[:taggable_type] = "Budget::Investment"
          attributes[:context] = "ml_tags"
          Tagging.create!(attributes)
        end
      end
    end
  end

  def update_machine_learning_info_for(kind)
    MachineLearningInfo.find_or_create_by!(kind: kind)
                       .update!(generated_at: job.started_at, script: job.script)
  end

  def set_previous_modified_date
    {
      MachineLearning.proposals_tags_filename => last_modified_date_for(MachineLearning.proposals_tags_filename),
      MachineLearning.proposals_taggings_filename => last_modified_date_for(MachineLearning.proposals_taggings_filename),
      MachineLearning.investments_tags_filename => last_modified_date_for(MachineLearning.investments_tags_filename),
      MachineLearning.investments_taggings_filename => last_modified_date_for(MachineLearning.investments_taggings_filename),
      MachineLearning.debates_tags_filename => last_modified_date_for(MachineLearning.debates_tags_filename),
      MachineLearning.debates_taggings_filename => last_modified_date_for(MachineLearning.debates_taggings_filename),
      MachineLearning.proposals_related_filename => last_modified_date_for(MachineLearning.proposals_related_filename),
      MachineLearning.investments_related_filename => last_modified_date_for(MachineLearning.investments_related_filename),
      MachineLearning.proposals_comments_summary_filename => last_modified_date_for(MachineLearning.proposals_comments_summary_filename),
      MachineLearning.investments_comments_summary_filename => last_modified_date_for(MachineLearning.investments_comments_summary_filename)
    }
  end

  def last_modified_date_for(filename)
    return nil unless File.exist? MachineLearning.data_folder.join(filename)

    File.mtime MachineLearning.data_folder.join(filename)
  end

  def updated_file?(filename)
    return false unless File.exist? MachineLearning.data_folder.join(filename)
    return true if previous_modified_date[filename].blank?

    last_modified_date_for(filename) > previous_modified_date[filename]
  end

  def handle_error(error)
    message = error.message
    backtrace = error.backtrace.select { |line| line.include?("machine_learning.rb") }
    full_error = ([message] + backtrace).join("<br>")
    job.update!(finished_at: Time.current, error: full_error)
    Mailer.machine_learning_error(user).deliver_later
  end

  def fail_job(message)
    job.update!(error: message, finished_at: Time.current)
    Mailer.machine_learning_error(user).deliver_later
  end
end
