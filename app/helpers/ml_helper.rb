module MlHelper
  class LLMError < StandardError; end

  def self.llm_enabled?
    # Basic settings check.
    # Llm::Config.context handles the actual keys, so we just check feature flags here.
    Setting['feature.machine_learning'] &&
      Setting['llm.provider'].present? &&
      Setting['llm.model'].present?
  end


  # -------------------------------------------------------------------------
  # SUMMARIZATION (Themes + Quotes + Sentiment)
  # -------------------------------------------------------------------------
  def self.summarize_comments(comments, context = nil)
    return nil unless llm_enabled?
    return nil if comments.blank?

    combined_text = comments.is_a?(Array) ? comments.join("\n") : comments

    # Smart Truncation
    max_tokens = Setting['llm.max_tokens']&.to_i || 3000 # Bumped up slightly
    max_chars = max_tokens * 4
    if combined_text.length > max_chars
      combined_text = "...(previous comments truncated)...\n" + combined_text.last(max_chars)
    end

    # 1. System Prompt: Ask for STRUCTURED DATA, not Markdown text
    system_prompt = <<~PROMPT
      You are a qualitative data analyst.
      Analyze the public comments provided and extract key insights.

      OUTPUT FORMAT:
      Return ONLY valid JSON with this exact structure:
      {
        "executive_summary": "One sentence summary of the overall sentiment.",
        "themes": [
          {
            "name": "Theme Title",
            "explanation": "Brief explanation of this theme.",
            "quotes": ["Direct Quote 1", "Direct Quote 2"]
          }
        ],
        "sentiment": {
          "positive": 0,
          "negative": 0,
          "neutral": 0
        }
      }

      RULES:
      1. 'sentiment' percentages must sum to 100.
      2. Extract 3-5 distinct themes.
      3. Quotes must be verbatim from the text.
      4. Do NOT use Markdown formatting in the JSON values.
    PROMPT

    user_prompt = <<~PROMPT
      #{context ? "CONTEXT: #{context}" : ''}

      COMMENTS TO ANALYZE:
      #{combined_text}
    PROMPT

    begin
      # 2. Call LLM
      chat = Llm::Config.context.chat(model: Setting['llm.model'])
      chat.with_instructions(system_prompt)
      response = chat.ask(user_prompt).content

      # 3. Clean & Parse JSON
      json_str = response.gsub(/```json|```/, '').strip
      data = JSON.parse(json_str)

      # 4. Construct the Markdown Body manually (Ruby side)
      # This ensures perfect formatting every time.
      markdown_parts = []

      # Part A: Executive Summary
      if data["executive_summary"].present?
        markdown_parts << "**Executive Summary**: #{data['executive_summary']}"
      end

      # Part B: Themes Loop
      if data["themes"].is_a?(Array) && data["themes"].any?
        markdown_parts << "\n**Key Themes & Voices**:"

        data["themes"].each do |theme|
          # Header: * **Theme Name**: Explanation
          markdown_parts << "* **#{theme['name']}**: #{theme['explanation']}"

          # Quotes: > "Quote"
          if theme["quotes"].is_a?(Array)
            theme["quotes"].each do |quote|
              markdown_parts << "  > \"#{quote}\""
            end
          end
          markdown_parts << "" # Empty line between themes
        end
      end

      # 5. Return the compatible Hash structure
      return {
        "summary_markdown" => markdown_parts.join("\n"),
        "sentiment" => data["sentiment"] || { "positive" => 0, "negative" => 0, "neutral" => 0 }
      }

    rescue JSON::ParserError => e
      Rails.logger.warn "[MlHelper] JSON Parse Error: #{e.message}. Response: #{response}"
      # Fallback: Return raw text if JSON fails entirely
      return {
        "summary_markdown" => response,
        "sentiment" => { "positive" => 0, "negative" => 0, "neutral" => 0 }
      }
    rescue => e
      Rails.logger.error "[MlHelper] summarize_comments error: #{e.message}"
      return nil
    end
  end

  # -------------------------------------------------------------------------
  # TAGGING (Robust & Noun-Constrained)
  # -------------------------------------------------------------------------
  def self.generate_tags(text, max_tags = 5)
    return [] unless llm_enabled?
    return [] if text.blank?

    # Smart Truncation to save tokens but keep context
    # We take the title + first 1000 chars of description
    truncated_text = text.truncate(1500)

    system_prompt = <<~PROMPT
      You are an expert taxonomist for a civic participation platform.
      Your goal is to extract specific, high-value topic tags from user input.

      STRICT RULES:
      1. Generate exactly #{max_tags} tags.
      2. Tags must be SPECIFIC nouns or phrases (e.g., use "Urban Planning", not "Planning").
      3. EXCLUDE generic meta-words: "Question", "Comment", "Feedback", "Issue", "Problem", "Suggestion", "Idea".
      4. EXCLUDE very short words (less than 3 characters) unless they are well-known acronyms (e.g., "NHS", "CO2").
      5. FORMAT: Return ONLY a raw JSON array of strings. Do not include markdown code blocks.

      Example Output: ["Public Transport", "Cycle Lanes", "Air Quality", "Budget 2025"]
    PROMPT

    user_prompt = <<~PROMPT
      Analyze the following text and extract the top #{max_tags} tags:

      TEXT:
      #{truncated_text}
    PROMPT

    begin
      # 1. Call the LLM
      chat = Llm::Config.context.chat(model: Setting['llm.model'])
      chat.with_instructions(system_prompt)
      response = chat.ask(user_prompt).content.strip

      # 2. Clean the response (remove Markdown backticks if the AI adds them)
      clean_json = response.gsub(/```json|```/, '').strip

      # 3. Parse JSON safely
      tags = JSON.parse(clean_json)

      # 4. Final Sanity Check (Ruby side)
      # We filter out anything that slipped through the LLM's logic
      tags.select do |tag|
        tag.is_a?(String) &&
          tag.length > 2 &&
          !tag.match?(/^(comment|question|feedback|suggestion)$/i)
      end.take(max_tags)

    rescue JSON::ParserError
      Rails.logger.warn "[MlHelper] Failed to parse tags JSON: #{response}"
      # Fallback: try to split by commas if JSON fails
      response.split(',').map(&:strip).reject(&:blank?)
    rescue => e
      Rails.logger.error "[MlHelper] generate_tags error: #{e.message}"
      []
    end
  end

  # -------------------------------------------------------------------------
  # RELATED CONTENT (Selector Pattern)
  # -------------------------------------------------------------------------
  def self.find_similar_content(source_text, candidate_texts, max_results = 3)
    return [] unless llm_enabled?
    return [] if source_text.blank? || candidate_texts.blank?

    # Format candidates
    candidates_formatted = candidate_texts.map.with_index do |text, index|
      "ID_#{index}: #{text.truncate(150)}"
    end.join("\n")

    system_prompt = <<~PROMPT
      You are a semantic matching engine.
      Identify candidates most semantically related to the SOURCE.

      Criteria:
      1. Shared topic/problem domain.
      2. Similar solution/location.

      Output:
      Return strictly a JSON array of the top #{max_results} matching IDs (integers).
      Example: [0, 5, 12]
    PROMPT

    user_prompt = <<~PROMPT
      SOURCE:
      #{source_text.truncate(500)}

      CANDIDATES:
      #{candidates_formatted}

      JSON OUTPUT (Top #{max_results} IDs):
    PROMPT

    begin
      # CHANGE: Use your custom config context
      chat = Llm::Config.context.chat(model: Setting['llm.model'])

      chat.with_instructions(system_prompt)
      response = chat.ask(user_prompt)

      selected_indices = parse_json_list(response.content)

      selected_indices.select { |i| i.is_a?(Integer) && i >= 0 && i < candidate_texts.size }
    rescue => e
      Rails.logger.error "[MlHelper] find_similar_content error: #{e.message}"
      (0...[candidate_texts.size, max_results].min).to_a
    end
  end

  # -------------------------------------------------------------------------
  # UTILITIES
  # -------------------------------------------------------------------------
  private

  def self.parse_json_list(content)
    json_str = content[content.index('[')..content.rindex(']')] rescue nil
    return [] unless json_str
    JSON.parse(json_str)
  rescue JSON::ParserError
    []
  end

  def self.max_tokens_to_words(tokens)
    (tokens * 0.75).to_i
  end

  def self.create_fallback_summary(comments)
    return '' if comments.blank?
    summary = ["**Automated Fallback Summary:**"]
    Array(comments).take(3).each do |c|
      summary << "- " + c.split('.').first(2).join('.') + "."
    end
    summary.join("\n")
  end
end
