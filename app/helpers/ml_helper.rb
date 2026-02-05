# app/helpers/ml_helper.rb
module MLHelper
  class LLMError < StandardError; end

  # Configuration from Settings
  def self.llm_config
    {
      model: llm_model_name,
      temperature: Setting['llm.temperature']&.to_f || 0.3,
      max_tokens: Setting['llm.max_tokens']&.to_i || 500,
      # Add any other RubyLLM specific config
    }.compact
  end

  def self.llm_model_name
    # Map provider settings to RubyLLM model names
    provider = Setting['llm.provider']&.presence || ENV['LLM_PROVIDER'] || 'openai'
    model = Setting['llm.model']&.presence

    # If no specific model is set, use reasonable defaults per provider
    if model.present?
      model
    else
      case provider.downcase
      when 'openai'
        'gpt-3.5-turbo'
      when 'anthropic'
        'claude-3-haiku'
      when 'gemini', 'vertex_ai'
        'gemini-2.0-flash'
      when 'ollama'
        'llama3.2'
      when 'azure_openai'
        'gpt-35-turbo'
      else
        'gpt-3.5-turbo' # Fallback
      end
    end
  end

  def self.llm_configured?
    Setting['feature.machine_learning'] && Setting['llm.provider'].present?
  end

  def self.configure_rubyllm
    # Configure RubyLLM based on settings
    provider = Setting['llm.provider']&.presence || 'openai'

    case provider.downcase
    when 'openai'
      RubyLLM.register_provider :openai do |config|
        config.api_key = Setting['llm.openai_api_key'] || ENV['OPENAI_API_KEY']
        config.uri_base = Setting['llm.base_url'] if Setting['llm.base_url'].present?
      end
    when 'anthropic'
      RubyLLM.register_provider :anthropic do |config|
        config.api_key = Setting['llm.anthropic_api_key'] || ENV['ANTHROPIC_API_KEY']
      end
    when 'azure_openai'
      RubyLLM.register_provider :azure_openai do |config|
        config.api_key = Setting['llm.azure_openai_api_key'] || ENV['AZURE_OPENAI_API_KEY']
        config.deployment = Setting['llm.deployment']
        config.api_version = Setting['llm.api_version'] || '2023-12-01-preview'
      end
    when 'ollama'
      RubyLLM.register_provider :ollama do |config|
        config.uri_base = Setting['llm.base_url'] || 'http://localhost:11434'
      end
    when 'gemini', 'vertex_ai'
      RubyLLM.register_provider :google do |config|
        config.api_key = Setting['llm.google_api_key'] || ENV['GOOGLE_API_KEY']
        config.project_id = Setting['llm.project_id']
        config.location = Setting['llm.location'] || 'us-central1'
      end
    end

    # Set the default provider
    RubyLLM.default_provider = provider.downcase.to_sym
  end

  def self.summarize_comments(comments, context = nil)
    return '' unless llm_configured?
    return '' if comments.blank?

    combined_text = comments.is_a?(Array) ? comments.join("\n\n") : comments

    # Truncate if too long (respect token limits)
    max_length = Setting['llm.max_tokens']&.to_i || 500
    if combined_text.length > (max_length * 4) # Rough estimate: 4 chars per token
      combined_text = combined_text.first(max_length * 4)
    end

    system_prompt = <<~PROMPT
      You are an assistant that summarizes public comments for participatory budgeting projects.
      Create a concise summary that captures the main points, concerns, and suggestions from the comments.
      Focus on actionable insights and common themes.
      Format the summary as bullet points.
      Keep the summary under #{max_tokens_to_words(max_length)} words.
    PROMPT

    user_prompt = <<~PROMPT
      #{context ? "Context: #{context}\n\n" : ''}
      Summarize the following comments:

      #{combined_text}

      Provide a clear, concise summary with key points as bullet points.
    PROMPT

    # Use RubyLLM for the chat
    begin
      chat = RubyLLM.chat(model: llm_model_name)
      chat.with_instructions(system_prompt)

      response = chat.ask(user_prompt)
      response.content.strip
    rescue => e
      Rails.logger.error "MLHelper summarize_comments error: #{e.message}"
      # Fallback to a simple summary if LLM fails
      create_fallback_summary(comments)
    end
  end

  def self.generate_tags(text, max_tags = 5)
    return [] unless llm_configured?
    return [] if text.blank?

    system_prompt = <<~PROMPT
      You are an assistant that extracts relevant tags from text.
      Extract key topics, themes, and categories mentioned in the text.
      Return only the tags as a comma-separated list.
      Be concise and relevant. Extract up to #{max_tags} tags.
    PROMPT

    user_prompt = <<~PROMPT
      Extract up to #{max_tags} relevant tags from this text:

      #{text}

      Return only a comma-separated list of tags.
    PROMPT

    begin
      chat = RubyLLM.chat(model: llm_model_name)
      chat.with_instructions(system_prompt)

      response = chat.ask(user_prompt)
      tags = response.content.split(',').map(&:strip).reject(&:blank?)

      # Clean up any explanations or extra text
      tags.map { |tag| tag.gsub(/["']/, '').gsub(/^tag[:\s]*/i, '').strip }
          .reject { |tag| tag.downcase.include?('tag') }
          .first(max_tags)
    rescue => e
      Rails.logger.error "MLHelper generate_tags error: #{e.message}"
      []
    end
  end

  def self.find_similar_content(source_text, candidate_texts, max_results = 3)
    return [] unless llm_configured?
    return [] if source_text.blank? || candidate_texts.blank?

    # For embeddings/similarity, we might need a different approach
    # Let's use RubyLLM to compare texts
    similarities = candidate_texts.map.with_index do |candidate, index|
      similarity = calculate_text_similarity(source_text, candidate)
      { text: candidate, similarity: similarity, index: index }
    end

    similarities.sort_by { |item| -item[:similarity] }
                .first(max_results)
                .map { |item| item[:index] }
  rescue => e
    Rails.logger.error "MLHelper find_similar_content error: #{e.message}"
    # Return first N as fallback
    (0...[candidate_texts.size, max_results].min).to_a
  end

  # Advanced: Use LLM to calculate similarity
  def self.calculate_text_similarity(text1, text2)
    return 0.0 if text1.blank? || text2.blank?

    system_prompt = <<~PROMPT
      You are an assistant that compares the similarity between two texts.
      Return a similarity score between 0.0 and 1.0, where:
      - 0.0 means completely unrelated
      - 0.5 means somewhat related
      - 1.0 means very similar or identical in meaning

      Only return the numeric score, nothing else.
    PROMPT

    user_prompt = <<~PROMPT
      Compare these two texts and return a similarity score:

      Text 1: #{text1}

      Text 2: #{text2}

      Similarity score (0.0 to 1.0):
    PROMPT

    begin
      chat = RubyLLM.chat(model: llm_model_name)
      chat.with_instructions(system_prompt)

      response = chat.ask(user_prompt)
      score = response.content.strip.to_f

      # Clamp to 0-1 range
      [[score, 0.0].max, 1.0].min
    rescue => e
      Rails.logger.error "MLHelper calculate_text_similarity error: #{e.message}"
      # Simple fallback: check for common words
      fallback_similarity(text1, text2)
    end
  end

  # Batch processing for efficiency
  def self.batch_summarize_comments(comments_by_context)
    return {} unless llm_configured?
    return {} if comments_by_context.blank?

    summaries = {}

    # Process in batches to avoid rate limits
    comments_by_context.each_slice(batch_size).each do |batch|
      batch.each do |context, comments|
        summaries[context] = summarize_comments(comments, context)
      end

      # Add delay between batches
      sleep(batch_delay) if batch_delay > 0
    end

    summaries
  end

  # Generate embeddings using RubyLLM if available
  def self.generate_embedding(text)
    return [] unless llm_configured?
    return [] if text.blank?

    # Check if the model supports embeddings
    # For now, we'll return empty array
    # You might need to implement this based on your RubyLLM version
    []
  end

  private

  def self.max_tokens_to_words(tokens)
    (tokens * 0.75).to_i # Rough estimate: 0.75 words per token
  end

  def self.batch_size
    Setting['llm.batch_size']&.to_i || 5
  end

  def self.batch_delay
    Setting['llm.batch_delay']&.to_f || 1.0
  end

  def self.create_fallback_summary(comments)
    return '' if comments.blank?

    # Simple fallback: take first few sentences from each comment
    sentences = []

    Array(comments).each do |comment|
      # Simple sentence splitting
      comment_sentences = comment.split(/[.!?]+/).map(&:strip).reject(&:blank?)
      sentences << comment_sentences.first if comment_sentences.any?
      break if sentences.length >= 5
    end

    sentences.empty? ? '' : "Key points:\n- " + sentences.join("\n- ")
  end

  def self.fallback_similarity(text1, text2)
    return 0.0 if text1.blank? || text2.blank?

    # Simple word overlap similarity
    words1 = text1.downcase.split(/\W+/)
    words2 = text2.downcase.split(/\W+/)

    common_words = words1 & words2
    total_unique_words = (words1 + words2).uniq.size

    total_unique_words > 0 ? common_words.size.to_f / total_unique_words : 0.0
  end

  # Initialize RubyLLM configuration
  def self.initialize!
    return unless llm_configured?

    begin
      require 'rubyllm'
      configure_rubyllm
    rescue LoadError => e
      Rails.logger.error "RubyLLM gem not found: #{e.message}"
    rescue => e
      Rails.logger.error "Failed to configure RubyLLM: #{e.message}"
    end
  end
end

# Initialize when the module is loaded
MLHelper.initialize! if defined?(Rails)
