class Offers::TableActionsComponent < Admin::TableActionsComponent

  # Custom actions for Mutual Aid
  def confirm_button
    return unless record.is_a?(ProposalMatch) && record.accepted?

    action(:confirm,
           path: helpers.confirm_proposal_match_path(record),
           class: "button success tiny no-margin",
           icon: "handshake-o"
    )
  end

  def fulfill_button
    return unless record.is_a?(ProposalMatch) && record.confirmed?

    action(:fulfill,
           path: helpers.fulfill_proposal_match_path(record),
           class: "button success hollow tiny no-margin",
           method: :patch,
           data: { confirm: helpers.t("proposals.show.confirm_fulfillment_check") }
    )
  end

  private

    # ONLY override the paths to fix the UsersController routing crash.
    # Do not touch the options or text, so Admin::ActionComponent
    # renders its built-in SVGs!
    def edit_path
      options[:edit_path] || helpers.edit_offer_path(record)
    end

    def destroy_path
      options[:destroy_path] || helpers.offer_path(record)
    end
end
