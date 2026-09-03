load Rails.root.join("app", "controllers", "proposals_controller.rb")

class ProposalsController
  private

    alias_method :consul_allowed_params, :allowed_params
    def allowed_params
      consul_allowed_params + [:proposal_kind_id, sdg_goal_ids: []]
    end

    alias_method :consul_index_customization, :index_customization

    def index_customization
      # 1. Execute all standard Consul operations first
      consul_index_customization

      # 2. Extract by ID directly using the slug parameter to avoid join/load dependency crashes
      if params[:project].present?
        kind_id = ProposalKind.find_by(slug: params[:project])&.id
        target_id = kind_id || 0

        # Filter the main relation stack directly via the foreign key column name
        @resources = @resources.where(proposal_kind_id: target_id)

        # Filter the featured highlights collection array if present
        if @featured_proposals.present?
          @featured_proposals = @featured_proposals.where(proposal_kind_id: target_id)
        end
      end

      # 3. NEW: Capture the full, unpaginated dataset specifically for the map.
      # .geolocated ensures we only pass records that actually have map coordinates.
      @map_proposals = @resources.geolocated.unscope(:limit, :offset)
    end
end
