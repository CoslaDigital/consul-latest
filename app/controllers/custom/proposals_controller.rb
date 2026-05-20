load Rails.root.join("app", "controllers", "proposals_controller.rb")

class ProposalsController
  private

    alias_method :consul_allowed_params, :allowed_params

    def allowed_params
      # 1. Fetch the base structural array of parameters from Consul
      base_attributes = consul_allowed_params

      # 2. Append our custom scalar keys and complex structure keys cleanly
      base_attributes + [:proposal_kind_id, sdg_goal_ids: []]
    end
end
