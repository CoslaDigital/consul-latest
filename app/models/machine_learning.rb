# app/models/machine_learning.rb
class MachineLearning
  attr_reader :user, :script, :previous_modified_date
  attr_accessor :job

  SCRIPTS_FOLDER = Rails.root.join("public", "machine_learning", "scripts").freeze

  def initialize(job)
    @job = job
    @user = job.user
    @previous_modified_date = set_previous_modified_date
  end

  def data_folder
    self.class.data_folder
  end

  def run
    # Check if ML is enabled
    unless Setting['feature.machine_learning']
      job.update!(error: "Machine learning feature is not enabled", finished_at: Time.current)
      Mailer.machine_learning_error(user).deliver_later
      return false
    end

    # Check if LLM is configured
    unless llm_configured?
      job.update!(error: "LLM not properly configured. Please configure provider and model in settings.", finished_at: Time.current)
      Mailer.machine_learning_error(user).deliver_later
      return false
    end

    Llm::Config.context

    # Map Python scripts to Ruby methods
    case job.script
    when 'budgets_summary_comments_textrank.py'
      generate_budget_comments_summary
    when 'proposals_summary_comments_textrank.py'
      generate_proposal_comments_summary
    when 'budgets_tags_textrank.py'
      generate_budget_tags
    when 'proposals_tags_textrank.py'
      generate_proposal_tags
    when 'budgets_related_content_textrank.py'
      generate_budget_related_content
    when 'proposals_related_content_textrank.py'
      generate_proposal_related_content
    else
      # Fallback to original Python script execution
      return unless run_machine_learning_scripts
      import_results
    end

    job.update!(finished_at: Time.current)
    Mailer.machine_learning_success(user).deliver_later
    true
  rescue Exception => e
    handle_error(e)
    raise e
  end

  # Budget Comments Summary (replaces budgets_summary_comments_textrank.py)
  def generate_budget_comments_summary
    # Check if this feature is enabled
    unless Setting['machine_learning.comments_summary']
      Rails.logger.info "Comments summary feature is disabled in settings"
      job.update!(finished_at: Time.current)
      return
    end

    Rails.logger.info "[MachineLearning] Starting budget comments summarization"

    # Clean up existing summaries
    cleanup_investments_comments_summary!

    results = []
    investments = Budget::Investment.with_comments
    total = investments.count
    processed = 0

    investments.find_each(batch_size: 10) do |investment|
      next unless should_generate_summary_for?(investment)

      comments = investment.comments.not_hidden
                           .where("LENGTH(body) > 10")
                           .order(:created_at)
                           .pluck(:body)

      if comments.any?
        context = "Budget Investment: #{investment.title}"
        summary = generate_comments_summary(comments, context)

        # Save to database
        ml_summary = MlSummaryComment.find_or_initialize_by(
          commentable_id: investment.id,
          commentable_type: 'Budget::Investment'
        )
        ml_summary.body = summary
        ml_summary.save!

        # Add to results for file export
        results << {
          id: results.size,
          commentable_id: investment.id,
          commentable_type: 'Budget::Investment',
          body: summary
        }
      end

      processed += 1
      log_progress("budget comments", processed, total, investment.id)
    end

    # Save results to files (for compatibility)
    save_comments_summary_results(results, MachineLearning.investments_comments_summary_filename)

    update_machine_learning_info_for("comments_summary")

    Rails.logger.info "[MachineLearning] Completed budget comments summarization. Processed #{processed} investments."
  end

  # Proposal Comments Summary (replaces proposals_summary_comments_textrank.py)
  def generate_proposal_comments_summary
    unless Setting['machine_learning.comments_summary']
      Rails.logger.info "Comments summary feature is disabled in settings"
      job.update!(finished_at: Time.current)
      return
    end

    Rails.logger.info "[MachineLearning] Starting proposal comments summarization"

    cleanup_proposals_comments_summary!

    results = []
    proposals = Proposal.with_comments
    total = proposals.count
    processed = 0

    proposals.find_each(batch_size: 10) do |proposal|
      next unless should_generate_summary_for?(proposal)

      comments = proposal.comments.not_hidden
                         .where("LENGTH(body) > 10")
                         .order(:created_at)
                         .pluck(:body)

      if comments.any?
        context = "Proposal: #{proposal.title}"
        summary = generate_comments_summary(comments, context)

        ml_summary = MlSummaryComment.find_or_initialize_by(
          commentable_id: proposal.id,
          commentable_type: 'Proposal'
        )
        ml_summary.body = summary
        ml_summary.save!

        results << {
          id: results.size,
          commentable_id: proposal.id,
          commentable_type: 'Proposal',
          body: summary
        }
      end

      processed += 1
      log_progress("proposal comments", processed, total, proposal.id)
    end

    save_comments_summary_results(results, MachineLearning.proposals_comments_summary_filename)
    update_machine_learning_info_for("comments_summary")

    Rails.logger.info "[MachineLearning] Completed proposal comments summarization. Processed #{processed} proposals."
  end

  # Budget Tags (replaces budgets_tags_textrank.py)
  def generate_budget_tags
    unless Setting['machine_learning.tags']
      Rails.logger.info "Tags feature is disabled in settings"
      job.update!(finished_at: Time.current)
      return
    end

    Rails.logger.info "[MachineLearning] Starting budget tags generation"

    cleanup_investments_tags!

    tags = []
    taggings = []
    investments = Budget::Investment.all
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

    # Save to files (for compatibility)
    save_tags_results(tags, taggings,
                      MachineLearning.investments_tags_filename,
                      MachineLearning.investments_taggings_filename)

    # Import to database
    import_tags_from_arrays(tags, taggings, 'Budget::Investment')
    update_machine_learning_info_for("tags")

    Rails.logger.info "[MachineLearning] Completed budget tags generation. Processed #{processed} investments."
  end

  # Proposal Tags (replaces proposals_tags_textrank.py)
  def generate_proposal_tags
    unless Setting['machine_learning.tags']
      Rails.logger.info "Tags feature is disabled in settings"
      job.update!(finished_at: Time.current)
      return
    end

    Rails.logger.info "[MachineLearning] Starting proposal tags generation"

    cleanup_proposals_tags!

    tags = []
    taggings = []
    proposals = Proposal.all
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

  # Budget Related Content (replaces budgets_related_content_textrank.py)
  def generate_budget_related_content
    unless Setting['machine_learning.related_content']
      Rails.logger.info "Related content feature is disabled in settings"
      job.update!(finished_at: Time.current)
      return
    end

    Rails.logger.info "[MachineLearning] Starting budget related content generation"

    cleanup_investments_related_content!

    results = []
    investments = Budget::Investment.all.to_a
    total = investments.count
    processed = 0

    investments.each do |investment|
      source_text = "#{investment.title} #{investment.description}"

      candidates = investments.reject { |inv| inv.id == investment.id }
      candidate_texts = candidates.map { |inv| "#{inv.title} #{inv.description}" }

      similar_indices = find_similar_content(source_text, candidate_texts, 3)
      related_ids = similar_indices.map { |idx| candidates[idx].id }

      results << {
        id: investment.id
      }.tap do |hash|
        related_ids.each_with_index do |related_id, idx|
          hash["related_#{idx}"] = related_id
        end
      end

      processed += 1
      log_progress("budget related content", processed, total, investment.id)
    end

    save_related_content_results(results, MachineLearning.investments_related_filename)
    import_related_content_from_array(results, 'Budget::Investment')
    update_machine_learning_info_for("related_content")

    Rails.logger.info "[MachineLearning] Completed budget related content generation. Processed #{processed} investments."
  end

  # Proposal Related Content (replaces proposals_related_content_textrank.py)
  def generate_proposal_related_content
    unless Setting['machine_learning.related_content']
      Rails.logger.info "Related content feature is disabled in settings"
      job.update!(finished_at: Time.current)
      return
    end

    Rails.logger.info "[MachineLearning] Starting proposal related content generation"

    cleanup_proposals_related_content!

    results = []
    proposals = Proposal.all.to_a
    total = proposals.count
    processed = 0

    proposals.each do |proposal|
      source_text = "#{proposal.title} #{proposal.description}"

      candidates = proposals.reject { |p| p.id == proposal.id }
      candidate_texts = candidates.map { |p| "#{p.title} #{p.description}" }

      similar_indices = find_similar_content(source_text, candidate_texts, 3)
      related_ids = similar_indices.map { |idx| candidates[idx].id }

      results << {
        id: proposal.id
      }.tap do |hash|
        related_ids.each_with_index do |related_id, idx|
          hash["related_#{idx}"] = related_id
        end
      end

      processed += 1
      log_progress("proposal related content", processed, total, proposal.id)
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
      Dir[SCRIPTS_FOLDER.join("*.py")].map do |full_path_filename|
        {
          name: full_path_filename.split("/").last,
          description: description_from(full_path_filename)
        }
      end.sort_by { |script_info| script_info[:name] }
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
    MLHelper.summarize_comments(comments, context)
  end

  def generate_tags_from_text(text, max_tags = 5)
    MLHelper.generate_tags(text, max_tags)
  end

  def find_similar_content(source_text, candidate_texts, max_results = 3)
    MLHelper.find_similar_content(source_text, candidate_texts, max_results)
  end

  def llm_configured?
    self.class.llm_configured?
  end

  # Helper methods

  def should_generate_summary_for?(record)
    # Only regenerate if no summary exists or comments have been updated
    last_summary = MlSummaryComment.where(
      commentable_id: record.id,
      commentable_type: record.class.name
    ).order(created_at: :desc).first

    return true if last_summary.blank?

    latest_comment = record.comments.maximum(:updated_at)
    latest_comment.present? && latest_comment > last_summary.updated_at
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

    # Import tags
    tags.each do |tag_attrs|
      tag = Tag.find_or_create_by!(name: tag_attrs[:name].truncate(150))
      ids[tag_attrs[:id]] = tag.id
    end

    # Import taggings
    taggings.each do |tagging_attrs|
      tag_id = ids[tagging_attrs[:tag_id]]
      next unless tag_id

      Tagging.create!(
        tag_id: tag_id,
        taggable_id: tagging_attrs[:taggable_id],
        taggable_type: taggable_type,
        context: 'ml_tags'
      )
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
    FileUtils.mkdir_p data_folder
  end

  def export_proposals_to_json
    create_data_folder
    filename = data_folder.join(MachineLearning.proposals_filename)
    Proposal::Exporter.new.to_json_file(filename)
  end

  def export_budget_investments_to_json
    create_data_folder
    filename = data_folder.join(MachineLearning.investments_filename)
    Budget::Investment::Exporter.new(Array.new).to_json_file(filename)
  end

  def export_comments_to_json
    create_data_folder
    filename = data_folder.join(MachineLearning.comments_filename)
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
    json_file = data_folder.join(MachineLearning.proposals_comments_summary_filename)
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
    json_file = data_folder.join(MachineLearning.investments_comments_summary_filename)
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
    json_file = data_folder.join(MachineLearning.proposals_related_filename)
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
    json_file = data_folder.join(MachineLearning.investments_related_filename)
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
    json_file = data_folder.join(MachineLearning.proposals_tags_filename)
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

    json_file = data_folder.join(MachineLearning.proposals_taggings_filename)
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
    json_file = data_folder.join(MachineLearning.investments_tags_filename)
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

    json_file = data_folder.join(MachineLearning.investments_taggings_filename)
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
      proposals_tags_filename => last_modified_date_for(MachineLearning.proposals_tags_filename),
      proposals_taggings_filename => last_modified_date_for(MachineLearning.proposals_taggings_filename),
      investments_tags_filename => last_modified_date_for(MachineLearning.investments_tags_filename),
      investments_taggings_filename => last_modified_date_for(MachineLearning.investments_taggings_filename),
      proposals_related_filename => last_modified_date_for(MachineLearning.proposals_related_filename),
      investments_related_filename => last_modified_date_for(MachineLearning.investments_related_filename),
      proposals_comments_summary_filename => last_modified_date_for(MachineLearning.proposals_comments_summary_filename),
      investments_comments_summary_filename => last_modified_date_for(MachineLearning.investments_comments_summary_filename)
    }
  end

  def last_modified_date_for(filename)
    return nil unless File.exist? data_folder.join(filename)

    File.mtime data_folder.join(filename)
  end

  def updated_file?(filename)
    return false unless File.exist? data_folder.join(filename)
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
end
