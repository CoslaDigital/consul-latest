module Llm
  class Config
    class << self
      def context
        @context = RubyLLM.context do |config|
          Tenant.current_secrets.llm&.each do |key, value|
            config.send("#{key}=", value)
          end
          config.request_timeout = 60 # 1 min default
          config.max_retries = 2
          config.retry_interval = 1.0 # 1 second is plenty for cloud/general use
          config.retry_backoff_factor = 2
        end
      end

      def providers
        RubyLLM::Providers.constants.each_with_object({}) do |provider, hash|
          hash[provider] = { enabled: RubyLLM::Providers.const_get(provider).configured?(context.config) }
        end
      end
    end
  end
end
