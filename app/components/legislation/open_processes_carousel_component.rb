class Legislation::OpenProcessesCarouselComponent < ApplicationComponent
  attr_reader :processes

  def initialize(processes:)
    @processes = processes
  end

  def render?
    feature?("legislation") && processes.present? && processes.any?
  end

  private

    def is_active_class(index)
      index.zero? ? "is-active" : ""
    end
end
