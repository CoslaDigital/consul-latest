class ImageSuggestions::SuggestButtonComponent < ApplicationComponent
  attr_reader :form

  def initialize(form)
    @form = form
  end

  def render?
    ::Llm::Config.configured? && Setting["llm.use_ai_image_suggestions"].present?
  end

  private

    def resource_type
      form.object.class.name
    end

    def resource_id
      form.object.id if form.object.persisted?
    end
end
