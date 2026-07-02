# app/controllers/custom/admin/proposals_controller.rb
load Rails.root.join("app", "controllers", "admin", "proposals_controller.rb")

class Admin::ProposalsController
  # Prepend a module wrapper to intercept the base index method execution
  module ProjectTrackFiltering
    def index
      # 1. Allow the base controller to set up @proposals, sort orders, and searches
      super

      # 2. Immediately intercept the data array before respond_to compiles the HTML
      if params[:project].present?
        kind = ProposalKind.find_by(slug: params[:project])

        if kind && @proposals.present?
          # Remove pagination applied by super so we filter across the full base dataset
          base_scope = @proposals.except(:limit, :offset)

          # Apply our tracking category filter
          filtered_scope = base_scope.where(proposal_kind_id: kind.id)

          # Re-apply pagination boundaries against the newly filtered query stack
          @proposals = if params[:format] == "csv"
                         filtered_scope
                       else
                         filtered_scope.page(params[:page])
                       end
        else
          @proposals = Proposal.none.page(params[:page])
        end
      end
    end
  end

  prepend ProjectTrackFiltering
end
