# config/initializers/admin_base_controller_patch.rb

Rails.application.config.to_prepare do
  # Forcefully re-open Consul's Admin Base Controller after the engine boots
  Admin::BaseController.class_eval do

    # 1. Inject our new firewall before any action runs in the admin namespace
    before_action :enforce_strict_budget_editing

    private

      # 2. Your existing gatekeeper to allow both Admins and Process Managers
      def verify_administrator
        unless current_user.administrator? || current_user.process_manager?
          raise CanCan::AccessDenied.new(
            I18n.t("flash.actions.errors.not_allowed"),
            :read,
            :admin_dashboard
          )
        end
      end

      # 3. The firewall to block cross-editing of structural budget components
      def enforce_strict_budget_editing
        # Only restrict Process Managers who are not full Administrators
        return unless current_user&.process_manager? && !current_user&.administrator?

        # Define the controllers that manage the structure of a budget (excluding investments)
        restricted_controllers = %w[budgets budget_groups budget_headings budget_phases]

        if restricted_controllers.include?(controller_name)
          # Allow them to view the index/show lists
          return if action_name.in?(%w[index show])

          # Find the ID of the budget they are trying to modify
          # (It will be params[:id] on the budgets controller, and params[:budget_id] on nested controllers)
          target_budget_id = params[:budget_id] || params[:id]
          return unless target_budget_id

          budget = Budget.find_by(id: target_budget_id)

          # If they don't own the budget, kick them out immediately
          if budget && budget.author_id != current_user.id
            raise CanCan::AccessDenied.new(I18n.t("flash.actions.errors.not_allowed"))
          end
        end
      end

  end
end
