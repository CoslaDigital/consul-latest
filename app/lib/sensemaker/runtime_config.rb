module Sensemaker
  class RuntimeConfig
    attr_reader :setting, :llm_context

    def initialize(setting: Setting, llm_context: Llm::Config.context)
      @setting = setting
      @llm_context = llm_context
    end

    def provider
      setting["llm.sensemaker_provider"].to_s.downcase.strip
    end

    def model
      setting["llm.sensemaker_model"].to_s.presence
    end

    def model_for(role)
      case role.to_sym
      when :primary
        model
      when :fast
        setting["llm.sensemaker_fast_model"].to_s.presence || model
      else
        raise ArgumentError, "Unknown Sensemaker model role: #{role}"
      end
    end

    def adapter
      Llm::Config.sensemaker_adapter_for(provider)
    end

    def compat_provider
      case provider
      when /openai/
        "openai"
      when /openrouter/
        "openrouter"
      when /mistral/
        "mistral"
      end
    end

    def api_key
      case adapter
      when "gemini"
        return llm_config.gemini_api_key.to_s.presence if llm_config.respond_to?(:gemini_api_key)

        nil
      when "openai-compatible"
        provider_name = compat_provider
        return nil if provider_name.blank?

        key_method = "#{provider_name}_api_key"
        return nil unless llm_config.respond_to?(key_method)

        llm_config.public_send(key_method).to_s.presence
      end
    end

    def base_url
      case adapter
      when "ollama"
        return llm_config.ollama_api_base.to_s.presence if llm_config.respond_to?(:ollama_api_base)
      when "openai-compatible"
        case compat_provider
        when "openai"
          return llm_config.openai_api_base.to_s.presence if llm_config.respond_to?(:openai_api_base)
        when "openrouter"
          return llm_config.openrouter_api_base.to_s.presence if llm_config.respond_to?(:openrouter_api_base)
        when "mistral"
          return llm_config.mistral_api_base.to_s.presence if llm_config.respond_to?(:mistral_api_base)
        end
      end

      nil
    end

    def vertex_project_id
      llm_config.vertexai_project_id.to_s
    end

    def vertex_location
      llm_config.vertexai_location.to_s.presence || "global"
    end

    def supported?
      adapter.present?
    end

    def validation_error
      if adapter.blank?
        return "Sensemaker LLM provider is not supported. Current provider: " \
               "#{provider.presence || "(not set)"}."
      end

      if adapter == "vertex" && vertex_project_id.blank?
        return "Vertex AI is not configured. Set tenant secrets llm.vertexai_project_id " \
               "(and optionally vertexai_location)."
      end

      if model.blank?
        return "Sensemaker requires an LLM model to be selected. " \
               "Set Sensemaker provider and model in Admin → Settings → LLM."
      end

      if adapter == "openai-compatible" && api_key.blank?
        return "Sensemaker requires an API key for provider '#{compat_provider}'. " \
               "Set tenant secret llm.#{compat_provider}_api_key."
      end

      if adapter == "gemini" && api_key.blank?
        return "Sensemaker requires a Gemini API key. Set tenant secret llm.gemini_api_key."
      end

      nil
    end

    private

      def llm_config
        llm_context.config
      end
  end
end
