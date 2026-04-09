class OffersController < ApplicationController
  # 1. Devise Authentication
  before_action :authenticate_user!, except: [:index, :show]

  # 2. The CanCanCan Magic - This handles authorization AND finds the @offer for you!
  load_and_authorize_resource

  def index
    @valid_orders = %w[created_at]

    @offers = Offer.all

    @offers = params[:filter] == "archived" ? Offer.archived : Offer.active

    # 2. Filter by specific status if requested (e.g., just Claimed)
    if params[:status].present?
      @offers = @offers.where(status: params[:status])
    end

    # 3. Handle Sorting Tabs
    @current_order = params[:order] || "newest"
    @offers = case @current_order
              when "most_active" then @offers.most_active
              else @offers.newest
              end

    @offers = @offers.page(params[:page])

    # Initialize the tag cloud for the sidebar
    @tag_cloud = TagCloud.new(Offer, params[:search])
  end

  def show
    if current_user
      @my_proposals = current_user.proposals.not_archived.not_retired
    end

    # 1. Define the valid sorting tabs for the comments section
    @valid_orders = %w[most_voted newest oldest]

    # 2. Grab the current selected order, or default to most_voted
    @current_order = params[:order].presence || "most_voted"

    # 3. Initialize the tree
    @comment_tree = CommentTree.new(@offer, params[:page], @current_order)
  end

  def new
    # @offer = Offer.new is automatically handled
  end

  def create
    # CanCanCan automatically builds @offer with offer_params,
    # but we must link it to the current user before saving.
    @offer.author = current_user

    if @offer.save
      redirect_to @offer, notice: "Your offer has been published to the community!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # @offer is automatically loaded and authorized
  end

  def update
    # CanCanCan automatically checks if they are the author based on ability.rb
    if @offer.update(offer_params)
      redirect_to @offer, notice: "Offer updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @offer.destroy
    redirect_to offers_url, notice: "Offer removed."
  end

  private

    def offer_params
      params.require(:offer).permit(
        :title,
        :description,
        :geozone_id,
        :tag_list,
        :terms_of_service,
        :status,
        image_attributes: [:id, :title, :cached_attachment, :attachment, :user_id]
      )
    end
end
