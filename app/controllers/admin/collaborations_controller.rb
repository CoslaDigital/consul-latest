# app/controllers/admin/collaborations_controller.rb
module Admin
  class CollaborationsController < Admin::BaseController
    def index
      @offers = Offer.all.order(created_at: :desc).page(params[:offer_page])
      @matches = ProposalMatch.includes(:proposal, :offer)
                              .order(created_at: :desc)
                   .page(params[:match_page])
    end

    def update_match
      @match = ProposalMatch.find(params[:id])
      if @match.update(status: params[:status])
        redirect_to admin_collaborations_path, notice: t("admin.collaborations.update.success")
      else
        redirect_to admin_collaborations_path, alert: t("admin.collaborations.update.error")
      end
    end

    def hide_offer
      @offer = Offer.find(params[:id])
      if @offer.update(hidden_at: Time.current)
        redirect_to admin_collaborations_path, notice: t("admin.collaborations.hide.success")
      else
        redirect_to admin_collaborations_path, alert: t("admin.collaborations.hide.error")
      end
    end
  end
end
