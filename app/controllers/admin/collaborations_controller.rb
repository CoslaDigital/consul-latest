module Admin
  class CollaborationsController < Admin::BaseController
    def index
      # Fetch all records with pagination
      @offers = Offer.all.order(created_at: :desc).page(params[:offer_page]).per(20)
      @matches = ProposalMatch.includes(:proposal, :offer)
                              .order(created_at: :desc)
                              .page(params[:match_page]).per(20)
    end

    def update_match
      @match = ProposalMatch.find(params[:id])
      if @match.update(status: params[:status])
        redirect_to admin_collaborations_path, notice: "Collaboration updated."
      end
    end

    def hide_offer
      @offer = Offer.find(params[:id])
      @offer.update(hidden_at: Time.current)
      redirect_to admin_collaborations_path, notice: "Offer hidden."
    end
  end
end
