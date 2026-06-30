# config/initializers/admin_base_controller_patch.rb

Rails.application.config.to_prepare do
  Admin::BaseController.class_eval do

    private

      # 1. The main gatekeeper (This is guaranteed to run on every admin request)
      def verify_administrator
        # Check basic access first
        unless current_user.administrator? || current_user.process_manager?
          raise CanCan::AccessDenied.new(
            I18n.t("flash.actions.errors.not_allowed"),
            :read,
            :admin_dashboard
          )
        end

        # If they are allowed into the admin panel, instantly run the firewall check!
        enforce_strict_editing_firewall
      end

      # 2. The unified firewall (No longer an independent before_action)
      def enforce_strict_editing_firewall
        # Only restrict Process Managers who are not full Administrators
        return unless current_user&.process_manager? && !current_user&.administrator?

        # --- BUDGET FIREWALL ---
        if controller_path.start_with?("admin/budgets", "admin/budget_")
          return if action_name.in?(%w[index])

          target_id = params[:budget_id] || params[:id]
          return unless target_id

          budget = Budget.find_by(id: target_id)
          if budget && budget.author_id != current_user.id
            raise CanCan::AccessDenied.new(I18n.t("flash.actions.errors.not_allowed"))
          end
        end

        # --- LEGISLATION FIREWALL ---
        if controller_path.start_with?("admin/legislation/")
          return if action_name.in?(%w[index])

          target_id = params[:process_id] || params[:legislation_process_id] || params[:id]
          return unless target_id

          process = Legislation::Process.find_by(id: target_id)
          if process && process.author_id != current_user.id
            raise CanCan::AccessDenied.new(I18n.t("flash.actions.errors.not_allowed"))
          end
        end
      end

  end
end
