module Admin::Widget::CardsActions
  extend ActiveSupport::Concern
  include Translatable
  include ImageAttributes

  def new
    @card.header = params[:header_card].present?
  end

  def create
    @card = Widget::Card.new(card_params)
    authorize! :create, @card

    if @card.save
      redirect_after_save(@card)
    else
      render :new
    end
  end

  def edit
    @pages = SiteCustomization::Page.all
  end

  def update
    # Store the card's original parent page before the update happens
    original_parent = @card.cardable

    if @card.update(card_params)
      # Pass the original parent to the redirect helper to check for changes
      redirect_after_save(@card, original_parent)
    else
      @pages = SiteCustomization::Page.all
      render :edit
    end
  end

  def destroy
    @card.destroy!
    redirect_to_index(notice: "Card was successfully destroyed.")
  end

  private

    # This is now the single source of truth for handling card parameters.
    def card_params
      all_params = params.require(:widget_card).permit(
        :link_url, :columns, :order, :header, :cardable_type, :cardable_id, :new_cardable_id,
        image_attributes: [:id, :user_id, :cached_attachment, :title, :_destroy],
        translations_attributes: [:id, :locale, :label, :title, :description, :link_text, :_destroy]
      )

      new_parent_param = all_params.delete(:new_cardable_id)

      if new_parent_param.present?
        if new_parent_param == "SiteCustomization::Page_" # The new value from the helper
          all_params[:cardable_type] = "SiteCustomization::Page"
          all_params[:cardable_id]   = nil
        else
          type, id = new_parent_param.split('_')
          all_params[:cardable_type] = type
          all_params[:cardable_id]   = id
        end
      elsif all_params[:cardable_type] == "homepage"
        # This corrects old, bad data if the dropdown isn't used
        all_params[:cardable_type] = "SiteCustomization::Page"
        all_params[:cardable_id]   = nil
      end

      all_params
    end

    # This helper contains the logic for redirecting after a successful save.
    def redirect_after_save(card, original_parent = nil)
      notice = t("admin.site_customization.pages.cards.#{params[:action]}.notice")

      # If the parent has changed, redirect to the new parent's page.
      if card.cardable != original_parent && card.cardable.present?
        # This generates a URL like /admin/site_customization/pages/7/cards
        redirect_to polymorphic_path([:admin, card.cardable, :widget_cards]), notice: notice
      else
        # Otherwise, redirect back to the original context (e.g., the homepage).
        redirect_to_index(notice: notice)
      end
    end

    # A placeholder that controllers must implement.
    def redirect_to_index(options = {})
      raise NotImplementedError, "You must define `redirect_to_index` in the including controller."
    end
end