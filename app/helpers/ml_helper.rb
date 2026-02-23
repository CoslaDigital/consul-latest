module MlHelper
  def self.summarize_comments(comments, context = nil, config: nil)
    # 1. Clean context to handle both String and localized Hash inputs
    clean_context = context.is_a?(Hash) ? (context[:en] || context.values.first) : context.to_s
    model_name = config&.[](:model) || Setting['llm.model']

    # 2. Qualitative Analyst Persona with JSON requirements
    system_prompt = <<~PROMPT
      You are a qualitative data analyst. Your goal is to analyze public comments and identify major recurring themes.

      Instructions:
      1. Identify 3-5 distinct Key Themes (e.g., "Safety Concerns", "Support for Green Space").
      2. For EACH theme, provide a brief explanation and select 1-2 DIRECT VERBATIM QUOTES from the text.
      3. Do not rewrite or summarize the quotes; extract them exactly as written.
      4. Provide a sentiment analysis score (percentages totaling 100).

      Return ONLY a JSON object with this structure:
      {
        "executive_summary": "1 sentence on overall sentiment: Positive/Negative/Mixed",
        "themes": [
          {
            "name": "Theme Name",
            "explanation": "Brief explanation",
            "quotes": ["Quote 1", "Quote 2"]
          }
        ],
        "sentiment": {"positive": 0, "negative": 0, "neutral": 100}
      }
    PROMPT

    begin
      # 3. Native library call (now fixed by your secrets.yml nesting)
      chat = Llm::Config.context.chat(model: model_name)
      chat.with_instructions(system_prompt)

      # Truncate input to avoid context window overflows
      response = chat.ask("CONTEXT: #{clean_context}\n\nCOMMENTS TO ANALYZE:\n#{comments.join("\n").truncate(6000)}")

      # 4. Extract and parse JSON block
      json_match = response.content.match(/\{.*\}/m)
      return nil unless json_match
      data = JSON.parse(json_match[0])

      # 5. Build the Markdown output matching your desired structure
      # This Ruby logic builds the exact "OUTPUT STRUCTURE" you requested
      markdown = "**Executive Summary**: #{data['executive_summary']}\n\n**Key Themes & Voices**:\n"

      (data['themes'] || []).each do |t|
        name = t['name'] || t['title']
        next if name.blank?
        markdown += "* **#{name}**: #{t['explanation']}\n"
        t['quotes']&.each { |q| markdown += "  > \"#{q}\"\n" }
        markdown += "\n" # Add spacing between themes
      end

      {
        "summary_markdown" => markdown.strip,
        "sentiment" => (data["sentiment"] || { "positive" => 0, "negative" => 0, "neutral" => 100 }),
        "usage" => { "total_tokens" => (response.input_tokens || 0) + (response.output_tokens || 0) }
      }
    rescue => e
      Rails.logger.error "[MlHelper] Summarization Error: #{e.message}"
      nil
    end
  end

  def self.generate_tags(text, count = 5, config: nil)
    model_name = config&.[](:model) || Setting['llm.model']

    begin
      chat = Llm::Config.context.chat(model: model_name)
      chat.with_instructions("You are a categorization expert. Return ONLY a comma-separated list of up to #{count} tags for the text. No intro, no bullets.")

      response = chat.ask(text.truncate(2000))

      {
        "tags" => response.content.split(",").map(&:strip).reject(&:blank?),
        "usage" => { "total_tokens" => (response.input_tokens || 0) + (response.output_tokens || 0) }
      }
    rescue => e
      Rails.logger.error "[MlHelper] Tagging Error: #{e.message}"
      nil
    end
  end
end
