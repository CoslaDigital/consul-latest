class OffersController < ApplicationController
  # Consul uses Devise or similar for auth
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_offer, only: [:show, :edit, :update, :destroy]
  before_action :verify_author, only: [:edit, :update, :destroy]

  def index
    # We only want to show available offers in the public feed
    @offers = Offer.active.sort_by_created_at.page(params[:page])
  end

  def show
    # For the "Match" UI: If the user is logged in, find all their active proposals (Asks)
    # so they can select which proposal they want to link to this Offer.
    if current_user
      @my_proposals = current_user.proposals.not_archived.not_retired
    end
  end

  def new
    @offer = Offer.new
  end

  def create
    @offer = current_user.offers.build(offer_params)

    if @offer.save
      redirect_to @offer, notice: "Your offer has been published to the community!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @offer.update(offer_params)
      redirect_to @offer, notice: "Offer updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    # Using acts_as_paranoid, this will set hidden_at
    @offer.destroy
    redirect_to offers_url, notice: "Offer removed."
  end

  private

    def set_offer
      @offer = Offer.find(params[:id])
    end

    def offer_params
      # geozone_id and tag_list are crucial for the matchmaking logic
      params.require(:offer).permit(:title, :description, :geozone_id, :tag_list)
    end

    def verify_author
      unless @offer.author == current_user || current_user.administrator?
        redirect_to offers_path, alert: "You are not authorized to edit this offer."
      end
    end
end
