module Sensemaker
  class RuntimeConfig
    attr_reader :setting, :llm_context

    def initialize(setting: Setting, llm_context: Llm::Config.context)
      @setting = setting
      @llm_context = llm_context
    end

    def provider
      setting["llm.provider"].to_s.downcase.strip
    end

    def model
      setting["llm.model"].to_s.presence
    end

    def adapter
      case provider
      when /vertex/
        "vertex"
      when /gemini/
        "gemini"
      when /ollama/
        "ollama"
      when /openai/, /openrouter/, /mistral/
        "openai-compatible"
      end
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
      when "openai-compatible"
        provider_name = compat_provider
        return nil if provider_name.blank?

        key_method = "#{provider_name}_api_key"
        return nil unless llm_config.respond_to?(key_method)

        return llm_config.public_send(key_method).to_s.presence
      end

      nil
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
      cli_supported?
    end

    def cli_supported?
      adapter.present? && adapter != "ollama"
    end

    private

      def llm_config
        llm_context.config
      end
  end
end
