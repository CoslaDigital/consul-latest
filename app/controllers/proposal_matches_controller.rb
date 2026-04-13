class ProposalMatchesController < ApplicationController
  before_action :authenticate_user!
  # We use set_proposal_match for every action that needs to find a specific ID
  before_action :set_proposal_match, only: [:accept, :confirm, :reject, :fulfill, :destroy]

  def create
    @proposal_match = ProposalMatch.new(proposal_match_params)
    if @proposal_match.save
      # Notify the receiver (dynamic based on who initiated)
      recipient = (@proposal_match.proposal.author == current_user) ? @proposal_match.offer.author : @proposal_match.proposal.author
      Notification.add(recipient, @proposal_match)

      redirect_back fallback_location: root_path, notice: t("proposal_matches.create.success")
    else
      redirect_back fallback_location: root_path, alert: @proposal_match.errors.full_messages.to_sentence
    end
  end

  def accept
    authorize! :accept, @proposal_match
    if @proposal_match.accepted!
      Notification.add(@proposal_match.proposal.author, @proposal_match)
      redirect_back fallback_location: root_path, notice: t("proposal_matches.accept.success")
    end
  end

  def confirm
    authorize! :confirm, @proposal_match
    if @proposal_match.confirmed!
      Notification.add(@proposal_match.offer.author, @proposal_match)
      redirect_back fallback_location: root_path, notice: t("proposal_matches.confirm.success")
    end
  end

  def fulfill
    authorize! :fulfill, @proposal_match
    if @proposal_match.fulfilled!
      Notification.add(@proposal_match.offer.author, @proposal_match)
      redirect_back fallback_location: root_path, notice: t("proposal_matches.fulfill.success")
    end
  end

  def reject
    authorize! :reject, @proposal_match
    @proposal_match.rejected!
    redirect_back fallback_location: root_path, notice: t("proposal_matches.reject.success")
  end

  private

    def set_proposal_match
      @proposal_match = ProposalMatch.find(params[:id])
    end

    def proposal_match_params
      # This is only used by the 'create' action
      params.require(:proposal_match).permit(:proposal_id, :offer_id)
    end
end
