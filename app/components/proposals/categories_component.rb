class Proposals::CategoriesComponent < ApplicationComponent
  attr_reader :current_project, :current_search

  def initialize(project:, search:)
    @current_project = project
    @current_search = search
  end

  # Only render the HTML block if there is at least one category to show
  def render?
    categories.any?
  end

  def categories
    @categories ||= begin
                      # Start with Consul's base category scope
                      scope = Tag.category.order(:name)

                      # If a project type is selected, filter categories to only those used by its proposals
                      if current_project_kind
                        scope = scope.joins(:taggings)
                                     .where(taggings: { taggable_type: "Proposal", taggable_id: proposals_in_project })
                                     .distinct
                      end

                      scope
                    end
  end

  def current_project_kind
    @current_project_kind ||= ProposalKind.find_by(slug: current_project) if current_project.present?
  end

  def proposals_in_project
    # Creates an efficient SQL subquery: SELECT id FROM proposals WHERE proposal_kind_id = ?
    Proposal.where(proposal_kind_id: current_project_kind.id).select(:id)
  end

  def active?(category)
    current_search == category.name
  end
end
