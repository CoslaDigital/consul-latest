class Admin::SiteCustomization::CardsController < Admin::SiteCustomization::BaseController
   puts "--- !!! EXECUTING inside NEW CONTROLLER ---"

  include Admin::Widget::CardsActions
  load_and_authorize_resource :page, class: "::SiteCustomization::Page", except: [:index]
  load_and_authorize_resource :card, through: :page, class: "Widget::Card", except: [:index, :update]
  helper_method :index_path

  def index
    puts "--- !!! EXECUTING inside NEW CONTROLLER ---"
    # Check if we are at the top-level route (no page_id)
    if params[:page_id].blank?
      # This is our standalone "All Cards" page
      authorize! :index, Widget::Card # Authorize the index action
      @cards = Widget::Card.all
      render "index_all" # Render a separate view to keep it clean
    else
      # This is the original logic for showing cards for a specific page
      # The 'load_and_authorize_resource' has already found @page and @cards
      # This is for a specific page. We need to load @page and @cards manually.
    @page = ::SiteCustomization::Page.find(params[:page_id])
    authorize! :show, @page # Authorize viewing the page
    @cards = @page.cards
    # Rails will automatically render 'index.html.erb' here
    end
  end

  private

    def index_path
      admin_site_customization_page_widget_cards_path(@page)
    end
end
