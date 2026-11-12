class Proposals::KindsComponent < ApplicationComponent
  attr_reader :current_project, :current_search

  def initialize(project:, search:)
    @current_project = project
    @current_search = search
  end

  # This built-in ViewComponent method automatically prevents the entire
  # HTML file from rendering if it returns false.
  def render?
    ProposalKind.count > 1
  end

  def kinds
    @kinds ||= ProposalKind.order(:name)
  end

  def all_types_active?
    current_project.blank?
  end

  def active?(kind)
    current_project == kind.slug
  end
end
