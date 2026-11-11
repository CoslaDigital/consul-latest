class Users::OfferTableActionsComponent < ApplicationComponent
  attr_reader :offer

  def initialize(offer)
    @offer = offer
  end

  private

    def edit_link
      link_to t("shared.edit"),
              edit_offer_path(offer),
              "aria-label": action_label(t("shared.edit")),
              class: "button hollow"
    end

    def destroy_button
      button_to t("shared.delete"),
                offer_path(offer),
                method: :delete,
                "aria-label": action_label(t("shared.delete")),
                class: "button hollow alert",
                data: { confirm: t("users.show.delete_alert", default: "Are you sure?") }
    end

    def action_label(action_text)
      t("shared.actions.label", action: action_text, name: offer.title)
    end
end
