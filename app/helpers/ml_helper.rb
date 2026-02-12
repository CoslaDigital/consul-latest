module MlHelper
  class LLMError < StandardError; end

  # -------------------------------------------------------------------------
  # TAGGING (Robust & Noun-Constrained)
  # -------------------------------------------------------------------------
  def self.generate_tags(text, max_tags = 5, config: nil)
    # 1. Configuration Guard: Prefer passed config to prevent DB lookups
    enabled = config ? config[:enabled] : Setting['feature.machine_learning']
    return [] unless enabled && text.present?

    model_name = config ? config[:model] : Setting['llm.model']
    return [] if model_name.blank?

    truncated_text = text.truncate(1500)

    system_prompt = <<~PROMPT
      You are an expert taxonomist for a civic participation platform.
      Your goal is to extract specific, high-value topic tags from user input.

      STRICT RULES:
      1. Generate exactly #{max_tags} tags.
      2. Tags must be SPECIFIC nouns or phrases.
      3. EXCLUDE generic meta-words: "Question", "Comment", "Feedback", "Issue", "Problem", "Suggestion", "Idea".
      4. EXCLUDE very short words (less than 3 characters).
      5. FORMAT: Return ONLY a raw JSON array of strings.
    PROMPT

    user_prompt = "Analyze the following text and extract the top #{max_tags} tags:\n\nTEXT:\n#{truncated_text}"

    begin
      chat = Llm::Config.context.chat(model: model_name)
      chat.with_instructions(system_prompt)
      response = chat.ask(user_prompt).content.strip

      # 2. Clean and Parse
      clean_json = response.gsub(/```json|```/, '').strip
      tags = JSON.parse(clean_json)

      # 3. Final Ruby-side Filtering
      tags.select do |tag|
        tag.is_a?(String) &&
          tag.length > 2 &&
          !tag.match?(/^(comment|question|feedback|suggestion|idea)$/i)
      end.take(max_tags)
    rescue => e
      Rails.logger.error "[MlHelper] generate_tags error: #{e.message}"
      []
    end
  end

  # -------------------------------------------------------------------------
  # SUMMARIZATION (Themes + Quotes + Sentiment)
  # -------------------------------------------------------------------------
  def self.summarize_comments(comments, context = nil, config: nil)
    enabled = config ? config[:enabled] : Setting['feature.machine_learning']
    return nil unless enabled && comments.present?

    model_name = config ? config[:model] : Setting['llm.model']
    max_tokens = (config ? config[:max_tokens] : Setting['llm.max_tokens'])&.to_i || 3000

    combined_text = comments.is_a?(Array) ? comments.join("\n") : comments
    max_chars = max_tokens * 4

    if combined_text.length > max_chars
      combined_text = "...(previous comments truncated)...\n" + combined_text.last(max_chars)
    end

    system_prompt = <<~PROMPT
      You are a qualitative data analyst. Return ONLY valid JSON with this exact structure:
      {
        "executive_summary": "One sentence summary.",
        "themes": [{"name": "Title", "explanation": "Brief text.", "quotes": ["Quote 1"]}],
        "sentiment": {"positive": 0, "negative": 0, "neutral": 0}
      }
    PROMPT

    user_prompt = "#{context ? "CONTEXT: #{context}\n\n" : ''}COMMENTS:\n#{combined_text}"

    begin
      chat = Llm::Config.context.chat(model: model_name)
      chat.with_instructions(system_prompt)
      response = chat.ask(user_prompt).content

      data = JSON.parse(response.gsub(/```json|```/, '').strip)

      # 4. Construct Markdown Body
      markdown_parts = []
      markdown_parts << "**Executive Summary**: #{data['executive_summary']}" if data["executive_summary"].present?

      if data["themes"].is_a?(Array)
        markdown_parts << "\n**Key Themes & Voices**:"
        data["themes"].each do |theme|
          markdown_parts << "* **#{theme['name']}**: #{theme['explanation']}"
          theme["quotes"]&.each { |q| markdown_parts << "  > \"#{q}\"" }
        end
      end

      {
        "summary_markdown" => markdown_parts.join("\n"),
        "sentiment" => data["sentiment"] || { "positive" => 0, "negative" => 0, "neutral" => 0 }
      }
    rescue => e
      Rails.logger.error "[MlHelper] summarize_comments error: #{e.message}"
      nil
    end
  end

  # -------------------------------------------------------------------------
  # RELATED CONTENT (Selector Pattern)
  # -------------------------------------------------------------------------
  def self.find_similar_content(source_text, candidate_texts, max_results = 3, config: nil)
    enabled = config ? config[:enabled] : Setting['feature.machine_learning']
    return [] unless enabled && source_text.present? && candidate_texts.present?

    model_name = config ? config[:model] : Setting['llm.model']

    candidates_formatted = candidate_texts.map.with_index do |text, index|
      "ID_#{index}: #{text.truncate(150)}"
    end.join("\n")

    system_prompt = "You are a semantic matching engine. Return strictly a JSON array of the top #{max_results} matching IDs (integers)."
    user_prompt = "SOURCE:\n#{source_text.truncate(500)}\n\nCANDIDATES:\n#{candidates_formatted}"

    begin
      chat = Llm::Config.context.chat(model: model_name)
      chat.with_instructions(system_prompt)
      response = chat.ask(user_prompt)

      selected_indices = parse_json_list(response.content)
      selected_indices.select { |i| i.is_a?(Integer) && i >= 0 && i < candidate_texts.size }
    rescue => e
      Rails.logger.error "[MlHelper] find_similar_content error: #{e.message}"
      (0...[candidate_texts.size, max_results].min).to_a
    end
  end

  private

  def self.parse_json_list(content)
    return [] if content.blank?

    # 1. Try to extract just the part between brackets [ ] to ignore "Here is your JSON:" filler
    json_match = content.match(/\[.*\]/m)
    if json_match
      json_str = json_match[0]

      # 2. Fix common LLM syntax errors: trailing commas or missing commas between quotes
      json_str = json_str.gsub(/,\s*\]/, ']') # Fix ["A", "B", ]

      begin
        return JSON.parse(json_str)
      rescue JSON::ParserError
        # If standard parsing fails, move to Regex recovery
      end
    end

    # 3. REGEX RECOVERY: If JSON is malformed, just grab everything inside double quotes
    # This recovers ["Tag 1" "Tag 2"] or other broken formats
    tags = content.scan(/"([^"\\]*(?:\\.[^"\\]*)*)"/).flatten

    # Filter out common false positives from the system prompt if they got picked up
    tags.reject { |t| t.downcase.match?(/^(themes|executive_summary|sentiment|positive|negative|neutral)$/) }
  end
end
