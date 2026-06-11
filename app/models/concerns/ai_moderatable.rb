module AiModeratable
  extend ActiveSupport::Concern

  included do
    after_commit :queue_ai_moderation, on: :create
  end

  def queue_ai_moderation
    self.delay.moderate_with_ai
  end

  def moderate_with_ai
    return if body.blank?
    return unless defined?(RubyLLM)

    model_name = Setting["llm.model"]
    provider_name = Setting["llm.provider"].to_s.downcase.to_sym
    return if model_name.blank? || provider_name.blank?

    return unless Setting.find_by(key: "llm.comment_moderation")&.enabled?

    # Define thresholds. Fall back to global defaults if settings don't exist.
    # Lower threshold = stricter moderation. Higher threshold = more relaxed.
    # Extract values directly from the new unified llm key settings
    flag_threshold = Setting["llm.moderation_flag_threshold"] || 0.4
    hidden_threshold = Setting["llm.moderation_hidden_threshold"] || 0.75

    system_prompt = <<~PROMPT
      You are an advanced automated content moderation system.
      Analyze the input comment and provide a floating-point score between 0.0 (completely innocent/safe) and 1.0 (extremely severe/violating) for each category.

      Categories:
      - hate_speech: Discriminatory language targeting protected groups, racism, sexism, bigotry.
      - harassment: Targeted attacks, bullying, cyberstalking, or persistent personal insults.
      - violence: Threats of physical harm, glorification of self-harm, or terrorist incitement.
      - sexual: Explicit or graphic adult content.
      - profanity_insults: General vulgarity, swearing, coarse language, or casual insults.

      STRICT JSON STRUCTURE RESPONSES ONLY. DO NOT INCLUDE ANY OUTSIDE TEXT OR MARKDOWN FENCES:
      {
        "categories": {
          "hate_speech": 0.05,
          "harassment": 0.12,
          "violence": 0.00,
          "sexual": 0.00,
          "profanity_insults": 0.45
        },
        "reasoning": "Brief operational justification for the scores."
      }
    PROMPT

    begin
      active_context = Llm::Config.context
      chat_params = { model: model_name, provider: provider_name }

      # Sync with your provider configurations
      if provider_name == :ollama
        chat_params[:assume_model_exists] = true
        active_context = active_context.dup { |c| c.request_timeout = 300 }
      elsif provider_name == :vertexai
        active_context = active_context.dup do |c|
          c.vertexai_location = Tenant.current_secrets.llm&.[]("vertexai_location") || "us-central1"
        end
      elsif provider_name == :anthropic || model_name.include?("claude")
        active_context = active_context.dup { |c| c.retry_interval = 12.0 }
      end

      chat = active_context.chat(**chat_params)
      chat.with_instructions(system_prompt)
      response = chat.ask(body.truncate(2000))

      raw_content = response.nil? || response.content.nil? ? nil : response.content
      raw_content = raw_content.text unless raw_content.is_a?(String)
      return if raw_content.blank?

      json_match = raw_content.match(/\{.*}/m)
      return if json_match.blank?

      data = JSON.parse(json_match[0])
      scores = data["categories"] || {}

      # --- AGGREGATION & THRESHOLD CHECKING LOGIC ---
      is_flagged = false
      is_hidden = false
      triggered_categories = []

      scores.each do |category, score|
        score_value = score.to_f

        # High severity violation triggers automatic hiding
        if score_value >= hidden_threshold.to_f
          is_hidden = true
          is_flagged = true
          triggered_categories << "#{category}(H:#{score_value})"
          # Moderate violation triggers a flag for review
        elsif score_value >= flag_threshold.to_f
          is_flagged = true
          triggered_categories << "#{category}(F:#{score_value})"
        end
      end

      # --- 1. CALCULATE FLAGS IF TRIGGERED ---
      calculated_flags = 0
      if is_flagged || is_hidden
        scores.each do |_, val|
          v = val.to_f
          calculated_flags += 4 if v >= hidden_threshold.to_f
          calculated_flags += 2 if v >= flag_threshold.to_f && v < hidden_threshold.to_f
        end
      else
        # If safe, retain the comment's current flags_count (usually 0)
        calculated_flags = self.flags_count
      end

      meta_payload = {
        model_used: model_name,
        evaluated_at: Time.current, # <--- Serves perfectly as your ai_moderated_at timestamp!
        scores: scores,
        reasoning: data["reasoning"],
        flagged: is_flagged,
        hidden: is_hidden
      }

      update_columns(
        flags_count: calculated_flags,
        hidden_at: is_hidden ? Time.current : self.hidden_at,
        ai_moderation_meta: meta_payload
      )

      if is_flagged || is_hidden
        Rails.logger.info "[AI Moderation] Comment ##{id} FLAGGED/HIDDEN by #{model_name}. " \
                            "Triggers: #{triggered_categories.join(', ')}. Reason: #{data['reasoning']}"
      else
        Rails.logger.info "[AI Moderation] Comment ##{id} marked CLEAN by #{model_name}."
      end

    rescue RubyLLM::Error => e
      Rails.logger.error "[AI Moderation] RubyLLM Error for Comment ##{id}: #{e.message}"
      raise e
    rescue JSON::ParserError
      Rails.logger.warn "[AI Moderation] JSON Parsing crash for Comment ##{id}. Content: #{raw_content.inspect}"
    rescue => e
      Rails.logger.error "[AI Moderation] Unexpected exception caught for Comment ##{id}: #{e.message}"
    end
  end
end
