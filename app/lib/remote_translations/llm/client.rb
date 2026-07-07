module RemoteTranslations
  module Llm
    class Client
      def call(fields_values, locale)
        fields_values.map do |text|
          request_translation(text, locale)
        end
      end

      private

        def chat
          @chat ||= ::Llm::Config.chat
        end

        def prompt
          @prompt ||= ::Llm::Config.prompts["remote_translation_prompt"]
        end

        def request_translation(text, locale)
          text_prompt = prompt % { input_text: text, output_locale: locale }
          chat.ask(text_prompt).content
        end
    end
  end
end
