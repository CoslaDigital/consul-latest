class ImageSuggestions::SuggestionsComponent < ApplicationComponent
  attr_reader :suggestions

  def initialize(suggestions)
    @suggestions = suggestions
  end

  private

    def images
      suggestions.results.presence&.photos || []
    end

    def errors
      suggestions.errors
    end

    def error_messages
      errors.join(", ")
    end
end
