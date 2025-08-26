class Admin::Widget::CardsController < Admin::BaseController
  include Admin::Widget::CardsActions

  load_and_authorize_resource :card, class: "Widget::Card"

  helper_method :index_path, :form_path

  protected # Use `protected` for methods that need to be helpers

    def index_path
      admin_homepage_path
    end

    # This method provides the correct URL to the form.
    def form_path
      if @card.new_record?
        # URL for the CREATE action
        admin_cards_path
      else
        # URL for the UPDATE action
        admin_card_path(@card)
      end
    end

  private # Keep internal-only methods private

    # This method is used by the concern to perform the actual redirect.
    def redirect_to_index(options = {})
      redirect_to admin_homepage_path, options
    end
end