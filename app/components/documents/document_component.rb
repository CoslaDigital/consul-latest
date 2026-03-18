class Documents::DocumentComponent < ApplicationComponent
  attr_reader :document, :show_destroy_link
  alias_method :show_destroy_link?, :show_destroy_link

  # We need these helpers for permissions and formatting
  use_helpers :can?, :number_to_human_size

  def initialize(document, show_destroy_link: false)
    @document = document
    @show_destroy_link = show_destroy_link
  end

  # Logic: Show link if Public OR if User is Admin/Author
  def linkable?
    visible? || can?(:update, document)
  end

  def visible?
    document.unrestricted?
  end

  def visibility_text
    visible? ? "Public" : "Private"
  end

  def visibility_class
    visible? ? "visibility-public" : "visibility-restricted"
  end
end
