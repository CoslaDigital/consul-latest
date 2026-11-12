class Proposals::CategoriesComponent < ApplicationComponent
  attr_reader :current_project, :current_search

  def initialize(project:, search:)
    @current_project = project
    @current_search = search
  end

  def proposals_in_project
    if current_project.present?
      project_kind = ProposalKind.find_by(slug: current_project)
      Proposal.where(proposal_kind_id: project_kind.id).select(:id) if project_kind
    end
  end

  # ViewComponent's 'call' method allows a component to render another component
  def call
    render Shared::CategoriesComponent.new(
      taggable_type: "Proposal",
      taggable_ids: proposals_in_project,
      current_search: current_search,
      url_method: :proposals_path,
      url_params: { project: current_project }
    )
  end
end
