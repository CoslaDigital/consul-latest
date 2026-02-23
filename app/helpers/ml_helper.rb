module MlHelper
  class LLMError < StandardError; end

  # -------------------------------------------------------------------------
  # TAGGING
  # -------------------------------------------------------------------------
  def self.generate_tags(text, max_tags = 5, config: nil)
    # Default safe return to prevent Model crashes
    safe_empty = { "tags" => [], "usage" => { "total_tokens" => 0 } }
    enabled = config ? config[:enabled] : Setting['feature.machine_learning']
    return safe_empty unless enabled && text.present?

    model_name = config ? config[:model] : Setting['llm.model']
    return safe_empty if model_name.blank?

    truncated_text = text.truncate(1500)
    system_prompt = "Return ONLY a raw JSON array of #{max_tags} strings."
    user_prompt = "Extract tags for: #{truncated_text}"

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
      safe_empty
    end
  end

  # -------------------------------------------------------------------------
  # SUMMARIZATION
  # -------------------------------------------------------------------------
  def self.summarize_comments(comments, context = nil, config: nil)
    clean_context = context.is_a?(Hash) ? (context[:en] || context.values.first) : context.to_s

    system_prompt = <<~PROMPT
      You are a data analyst. Return ONLY a JSON object.
      {
        "executive_summary": "Summary",
        "themes": [{"name": "Title", "explanation": "Desc", "quotes": ["Quote"]}],
        "sentiment": {"positive": 0, "negative": 0, "neutral": 100}
      }
    PROMPT

    begin
      chat = Llm::Config.context.chat(model: config&.[](:model) || Setting['llm.model'])
      chat.with_instructions(system_prompt)
      response = chat.ask("Context: #{clean_context}\nComments: #{comments.join("\n").truncate(4000)}")

      json_match = response.content.match(/\{.*\}/m)
      return nil unless json_match
      data = JSON.parse(json_match[0])

      markdown = "**Executive Summary**: #{data['executive_summary'] || data['summary']}\n\n**Key Themes & Voices**:\n"
      (data['themes'] || []).each do |t|
        name = t['name'] || t['title']
        next if name.blank?
        markdown += "* **#{name}**: #{t['explanation']}\n"
        t['quotes']&.each { |q| markdown += "  > \"#{q}\"\n" }
      end

      # Corrected Hash Syntax
      {
        "summary_markdown" => markdown,
        "sentiment" => (data["sentiment"] || { "positive" => 0, "negative" => 0, "neutral" => 100 }),
        "usage" => { "total_tokens" => (response.input_tokens || 0) + (response.output_tokens || 0) }
      }
    rescue => e
      Rails.logger.error "[MlHelper] Error: #{e.message}"
      nil
    end
  end

  # -------------------------------------------------------------------------
  # RELATED CONTENT
  # -------------------------------------------------------------------------
  def self.find_similar_content(source_text, candidate_texts, max_results = 3, config: nil)
    safe_empty = { "indices" => [], "usage" => { "total_tokens" => 0 } }
    enabled = config ? config[:enabled] : Setting['feature.machine_learning']
    return safe_empty unless enabled && source_text.present? && candidate_texts.present?

    model_name = config ? config[:model] : Setting['llm.model']
    candidates_formatted = candidate_texts.map.with_index { |t, i| "ID_#{i}: #{t.truncate(100)}" }.join("\n")

    begin
      chat = Llm::Config.context.chat(model: model_name)
      chat.with_instructions("Return a JSON array of the top #{max_results} matching IDs.")
      response = chat.ask("SOURCE: #{source_text}\nCANDIDATES:\n#{candidates_formatted}")

      indices = parse_json_list(response.content)
      valid_indices = indices.select { |i| i.is_a?(Integer) && i < candidate_texts.size }

      {
        "indices" => valid_indices,
        "usage" => { "total_tokens" => (response.input_tokens || 0) + (response.output_tokens || 0) }
      }
    rescue => e
      Rails.logger.error "[MlHelper] find_similar_content error: #{e.message}"
      safe_empty
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
      content.scan(/\d+/).map(&:to_i)
    end
end
