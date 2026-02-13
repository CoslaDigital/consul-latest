module MlHelper
  class LLMError < StandardError; end

  # -------------------------------------------------------------------------
  # TAGGING (Robust & Noun-Constrained)
  # -------------------------------------------------------------------------
  def self.generate_tags(text, max_tags = 5, config: nil)
    enabled = config ? config[:enabled] : Setting['feature.machine_learning']
    return { "tags" => [], "usage" => nil } unless enabled && text.present?

    model_name = config ? config[:model] : Setting['llm.model']
    return { "tags" => [], "usage" => nil } if model_name.blank?

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

      response = chat.ask(user_prompt)

      clean_json = response.content.strip.gsub(/```json|```/, '').strip
      tags = JSON.parse(clean_json)

      filtered_tags = tags.select do |tag|
        tag.is_a?(String) && tag.length > 2 && !tag.match?(/^(comment|question|feedback|suggestion|idea)$/i)
      end.take(max_tags)

      {
        "tags" => filtered_tags,
        "usage" => { "total_tokens" => (response.input_tokens || 0) + (response.output_tokens || 0) }
      }
    rescue => e
      Rails.logger.error "[MlHelper] generate_tags error: #{e.message}"
      { "tags" => [], "usage" => nil }
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
        "themes": [
          {
            "name": "Theme Title",
            "explanation": "Brief text.",
            "quotes": ["Quote 1", "Quote 2"]
          }
        ],
        "sentiment": {"positive": 0, "negative": 0, "neutral": 0}
      }

      OUTPUT RULES FOR MARKDOWN RENDERING:
      1. The Executive Summary should be bolded: **Executive Summary**: [text]
      2. Themes must be a top-level bullet point using '*': * **Theme Name**: [explanation]
      3. Quotes must be nested bullet points. Indent them with TWO SPACES and a '*':
         * **Theme Name**: explanation
           * "Direct quote 1"
           * "Direct quote 2"
    PROMPT

    user_prompt = "#{context ? "CONTEXT: #{context}\n\n" : ''}COMMENTS:\n#{combined_text}"

    begin
      chat = Llm::Config.context.chat(model: model_name)
      chat.with_instructions(system_prompt)
      response = chat.ask(user_prompt)

      data = JSON.parse(response.content.gsub(/```json|```/, '').strip)

      # 4. Construct Markdown Body
      markdown_parts = []
      markdown_parts << "**Executive Summary**: #{data['executive_summary']}" if data["executive_summary"].present?

      if data["themes"].is_a?(Array)
        markdown_parts << "\n**Key Themes & Voices**:"
        data["themes"].each do |theme|
          markdown_parts << "* **#{theme['name']}**: #{theme['explanation']}"
          theme["quotes"]&.each { |q| markdown_parts << "  * \"#{q}\"" }
        end
      end

      {
        "summary_markdown" => markdown_parts.join("\n"),
        "sentiment" => data["sentiment"] || { "positive" => 0, "negative" => 0, "neutral" => 0 },
        "usage" => { "total_tokens" => (response.input_tokens || 0) + (response.output_tokens || 0) }
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
    return { "indices" => [], "usage" => nil } unless enabled && source_text.present? && candidate_texts.present?

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
      valid_indices = selected_indices.select { |i| i.is_a?(Integer) && i >= 0 && i < candidate_texts.size }

      {
        "indices" => valid_indices,
        "usage" => { "total_tokens" => (response.input_tokens || 0) + (response.output_tokens || 0) }
      }
    rescue => e
      Rails.logger.error "[MlHelper] find_similar_content error: #{e.message}"
      { "indices" => (0...[candidate_texts.size, max_results].min).to_a, "usage" => nil }
    end
  end

  private

  def self.parse_json_list(content)
    return [] if content.blank?
    json_match = content.match(/\[.*\]/m)
    if json_match
      json_str = json_match[0].gsub(/,\s*\]/, ']')
      begin
        return JSON.parse(json_str)
      rescue JSON::ParserError
      end
    end
    tags = content.scan(/"([^"\\]*(?:\\.[^"\\]*)*)"/).flatten
    tags.reject { |t| t.downcase.match?(/^(themes|executive_summary|sentiment|positive|negative|neutral)$/) }
  end
end
