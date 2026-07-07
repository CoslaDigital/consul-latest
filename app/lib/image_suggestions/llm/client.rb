module ImageSuggestions
  module Llm
    class Client
      NUMBER_OF_IMAGES = 8

      def self.call(title:, description:)
        new(title: title, description: description).call
      end

      def initialize(title:, description:)
        @title = title
        @description = description
      end

      def call
        validate_llm_settings!
        return response if response.errors.any?

        search_query = generate_search_query
        return response if response.errors.any?

        results = ImageSuggestions::Pexels.search(search_query, per_page: NUMBER_OF_IMAGES)
        response.results = results
      rescue ::Pexels::APIError, RubyLLM::Error => e
        response.errors << e.message
      ensure
        return response
      end

      def response
        @response ||= Response.new
      end

      class Response
        attr_accessor :results
        attr_reader :errors

        def initialize
          @results = []
          @errors = []
        end
      end

      private

        def chat
          @chat ||= ::Llm::Config.chat
        end

        def generate_search_query
          if @title.blank? && @description.blank?
            response.errors << I18n.t("images.errors.messages.title_and_description_required")
            return
          end

          text_prompt = prompt % { title: @title, description: @description }
          chat.ask(text_prompt).content.strip
        end

        def prompt
          @prompt ||= ::Llm::Config.prompts["image_suggestion_prompt"]
        end

        def validate_llm_settings!
          unless ::Llm::Config.configured? && Setting["llm.use_ai_image_suggestions"].present?
            response.errors << I18n.t("images.errors.messages.llm_not_configured")
          end
        end
    end
  end
end
