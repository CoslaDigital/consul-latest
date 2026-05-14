class Offers::TableActionsComponent < Admin::TableActionsComponent
  # We can add custom actions specifically for Mutual Aid
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
end
