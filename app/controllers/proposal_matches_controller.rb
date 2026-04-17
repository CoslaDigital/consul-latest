class ProposalMatchesController < ApplicationController
  before_action :authenticate_user!

  # This one line replaces set_proposal_match AND all authorize! calls
  load_and_authorize_resource

  def create
    # @proposal_match is already initialized by load_and_authorize_resource
    if @proposal_match.save
      recipient = (@proposal_match.proposal.author == current_user) ? @proposal_match.offer.author : @proposal_match.proposal.author
      Notification.add(recipient, @proposal_match)

      # Trigger mailer here or in the model after_commit
      Mailer.proposal_match_created(@proposal_match).deliver_later

      redirect_back fallback_location: root_path, notice: t("proposal_matches.create.success")
    else
      redirect_back fallback_location: root_path, alert: @proposal_match.errors.full_messages.to_sentence
    end
  end

  def accept
    # @proposal_match is already found by load_and_authorize_resource
    if @proposal_match.accept!
      Notification.add(@proposal_match.proposal.author, @proposal_match)
      redirect_back fallback_location: root_path, notice: t("proposal_matches.accept.success")
    end
  end

  def confirm
    if @proposal_match.confirm!
      Notification.add(@proposal_match.offer.author, @proposal_match)
      redirect_back fallback_location: root_path, notice: t("proposal_matches.confirm.success")
    end
  end

  def fulfill
    if @proposal_match.fulfill!
      Notification.add(@proposal_match.offer.author, @proposal_match)
      redirect_back fallback_location: root_path, notice: t("proposal_matches.fulfill.success")
    end
  end

  def reject
    @proposal_match.reject!
    redirect_back fallback_location: root_path, notice: t("proposal_matches.reject.success")
  end

  private

    def proposal_match_params
      params.require(:proposal_match).permit(:proposal_id, :offer_id)
    end
end
