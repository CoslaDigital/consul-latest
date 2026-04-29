class OffersController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]

  load_and_authorize_resource except: [:mine]

  # GET /offers
  def index
    @valid_orders = %w[newest most_active]
    @current_order = @valid_orders.include?(params[:order]) ? params[:order] : "newest"

    # 1. Base Collection: Filter by Status
    @offers = case params[:status]
              when "claimed" then Offer.claimed
              when "withdrawn" then Offer.withdrawn
              else Offer.active
              end

    # 2. Filter by Search (Uses the scope we added to the Offer model)
    if params[:search].present?
      @offers = @offers.search(params[:search])
    end

    # 3. Apply Sorting
    if @current_order == "most_active"
      # Sorts by the number of associated matches (handshakes)
      @offers = @offers.joins(:proposal_matches)
                       .group("offers.id")
                       .order(Arel.sql("count(proposal_matches.id) DESC"))
    else
      @offers = @offers.newest
    end

    # 4. Finalize: Pagination and Sidebar Data
    @offers = @offers.page(params[:page])
    @tag_cloud = TagCloud.new(Offer, params[:search])
  end

  # GET /offers/:id
  def show
    # Used for the "I can help with this" sidebar dropdown
    if current_user
      @my_proposals = current_user.proposals.not_archived.not_retired
    end

    # Comment sorting logic
    @valid_orders = %w[most_voted newest oldest]
    @current_order = params[:order].presence || "most_voted"
    @comment_tree = CommentTree.new(@offer, params[:page], @current_order)
  end

  # GET /offers/new
  def new
    # @offer is initialized by load_and_authorize_resource
  end

  # POST /offers
  def create
    @offer.author = current_user

    if @offer.save
      redirect_to @offer, notice: t("offers.create.success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /offers/:id/edit
  def edit
    # @offer is loaded by load_and_authorize_resource
  end

  # PATCH/PUT /offers/:id
  def update
    if @offer.update(offer_params)
      redirect_to @offer, notice: t("offers.update.success", default: "Offer updated successfully.")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /offers/:id
  def destroy
    @offer.destroy!
    redirect_to offers_url, notice: t("offers.destroy.success", default: "Offer removed.")
  end

  # GET /offers/mine
  def mine
    # Since load_and_authorize_resource is skipped here, we manually fetch data
    @my_offers = current_user.offers.order(created_at: :desc)

    # Fetch matches for proposals OWNED by the current user (Inbound help)
    # Includes nested associations to prevent N+1 queries in the dashboard
    @inbound_matches = ProposalMatch.where(proposal_id: current_user.proposals.pluck(:id))
                                    .includes(:offer, proposal: :author)
                                    .order(created_at: :desc)

    # Authorize the 'mine' action manually for CanCanCan
    authorize! :mine, Offer
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
