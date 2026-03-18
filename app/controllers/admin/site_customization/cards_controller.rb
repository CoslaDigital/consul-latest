class Admin::SiteCustomization::CardsController < Admin::SiteCustomization::BaseController
  include Admin::Widget::CardsActions

  load_and_authorize_resource :page, class: "::SiteCustomization::Page"
  load_and_authorize_resource :card, through: :page, class: "Widget::Card"

  helper_method :index_path, :form_path

  def index
    # This action now correctly relies on CanCanCan to load @page and @cards
  end

  def edit
    @pages = SiteCustomization::Page.all
    render "admin/widget/cards/edit"
  end
  
  def new
    # @page is already loaded by CanCanCan
    # Manually build a new card belonging to this page
    @card = @page.cards.new
    
    # Load all pages for the "Parent Page" dropdown
    @pages = SiteCustomization::Page.all
    
    # Explicitly render the shared new/edit view
    render "admin/widget/cards/new"
  end
  
  protected # Use `protected` for methods that need to be helpers

    def index_path
      admin_site_customization_page_widget_cards_path(@page)
    end

    def form_path
      if @card.new_record?
        admin_site_customization_page_widget_cards_path(@page)
      else
        admin_site_customization_page_widget_card_path(@page, @card)
      end
    end


end