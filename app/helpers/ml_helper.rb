# app/helpers/ml_helper.rb
module MLHelper
  class LLMError < StandardError; end

  # Use your existing Llm::Config instead of custom configuration
  def self.llm_enabled?
    Setting['feature.machine_learning'] &&
      Setting['llm.provider'].present? &&
      Setting['llm.model'].present?
  end

  def self.summarize_comments(comments, context = nil)
    return '' unless llm_enabled?
    return '' if comments.blank?

    combined_text = comments.is_a?(Array) ? comments.join("\n\n") : comments

    # Truncate if too long (respect token limits)
    max_tokens = Setting['llm.max_tokens']&.to_i || 500
    if combined_text.length > (max_tokens * 4) # Rough estimate: 4 chars per token
      combined_text = combined_text.first(max_tokens * 4)
    end

    system_prompt = <<~PROMPT
      You are an assistant that summarizes public comments for participatory budgeting projects.
      Create a concise summary that captures the main points, concerns, and suggestions from the comments.
      Focus on actionable insights and common themes.
      Format the summary as bullet points.
      Keep the summary under #{max_tokens_to_words(max_tokens)} words.
    PROMPT

    user_prompt = <<~PROMPT
      #{context ? "Context: #{context}\n\n" : ''}
      Summarize the following comments:

      #{combined_text}

      Provide a clear, concise summary with key points as bullet points.
    PROMPT

    # Use RubyLLM with your existing configuration
    begin
      # Get the configured chat instance
      chat = RubyLLM.chat(model: Setting['llm.model'])
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
    return [] unless llm_enabled?
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
      chat = RubyLLM.chat(model: Setting['llm.model'])
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
    return [] unless llm_enabled?
    return [] if source_text.blank? || candidate_texts.blank?

    # For simplicity, use text similarity via LLM comparison
    # This could be optimized with embeddings if needed
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

  # Use LLM to calculate similarity between texts
  def self.calculate_text_similarity(text1, text2)
    return 0.0 if text1.blank? || text2.blank?

    # Simple fallback: common word overlap
    fallback_similarity(text1, text2)
  end

  # Batch processing for efficiency
  def self.batch_summarize_comments(comments_by_context)
    return {} unless llm_enabled?
    return {} if comments_by_context.blank?

    summaries = {}
    batch_size = Setting['llm.batch_size']&.to_i || 5
    batch_delay = Setting['llm.batch_delay']&.to_f || 1.0

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

  private

  def self.max_tokens_to_words(tokens)
    (tokens * 0.75).to_i # Rough estimate: 0.75 words per token
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
end
