module MlHelper
  def self.summarize_comments(comments, context = nil, config: nil)
    # 1. Clean context to handle both String and localized Hash inputs
    clean_context = context.is_a?(Hash) ? (context[:en] || context.values.first) : context.to_s
    model_name = config&.[](:model) || Setting['llm.model']

    # 2. Define the expected JSON structure for the LLM
    system_prompt = <<~PROMPT
      You are a data analyst. Return ONLY a JSON object.
      {
        "executive_summary": "A concise summary of the overall sentiment.",
        "themes": [{"name": "Theme Title", "explanation": "Description", "quotes": ["Direct quote"]}],
        "sentiment": {"positive": 0, "negative": 0, "neutral": 100}
      }
    PROMPT

    begin
      # 3. Use your library - Llm::Config.context now finds the nested secrets
      chat = Llm::Config.context.chat(model: model_name)
      chat.with_instructions(system_prompt)

      # Truncate input to avoid context window overflows (approx 4000 chars)
      response = chat.ask("Context: #{clean_context}\nComments: #{comments.join("\n").truncate(4000)}")

      # 4. Extract and parse JSON block from response
      json_match = response.content.match(/\{.*\}/m)
      return nil unless json_match
      data = JSON.parse(json_match[0])

      # 5. Build the Markdown output for the UI
      summary = data['executive_summary'] || data['summary']
      markdown = "**Executive Summary**: #{summary}\n\n**Key Themes & Voices**:\n"

      (data['themes'] || []).each do |t|
        name = t['name'] || t['title']
        next if name.blank?
        markdown += "* **#{name}**: #{t['explanation']}\n"
        t['quotes']&.each { |q| markdown += "  > \"#{q}\"\n" }
      end

      {
        "summary_markdown" => markdown,
        "sentiment" => (data["sentiment"] || { "positive" => 0, "negative" => 0, "neutral" => 100 }),
        "usage" => { "total_tokens" => (response.input_tokens || 0) + (response.output_tokens || 0) }
      }
    rescue => e
      Rails.logger.error "[MlHelper] Summarization Error: #{e.message}"
      nil
    end
  end

  # Use the same logic for tags to ensure consistency
  def self.generate_tags(text, config: nil)
    model_name = config&.[](:model) || Setting['llm.model']

    begin
      chat = Llm::Config.context.chat(model: model_name)
      chat.with_instructions("Return ONLY a comma-separated list of tags for the following text.")
      response = chat.ask(text.truncate(2000))

      {
        "tags" => response.content.split(",").map(&:strip),
        "usage" => { "total_tokens" => (response.input_tokens || 0) + (response.output_tokens || 0) }
      }
    rescue => e
      Rails.logger.error "[MlHelper] Tagging Error: #{e.message}"
      nil
    end
  end
end
