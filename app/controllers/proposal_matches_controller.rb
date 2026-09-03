class ProposalMatchesController < ApplicationController
  before_action :authenticate_user!

  # This one line replaces set_proposal_match AND all authorize! calls
  load_and_authorize_resource

  def create
    if @proposal_match.save
      # Identify who initiated and who should receive the email
      initiated_by_proposal_author = (@proposal_match.proposal.author == current_user)
      recipient = initiated_by_proposal_author ? @proposal_match.offer.author : @proposal_match.proposal.author

      Notification.add(recipient, @proposal_match)

      # Pass who initiated the match so the mailer sends the right message to the right person
      Mailer.proposal_match_created(@proposal_match.id, current_user.id).deliver_later

      redirect_back fallback_location: root_path, notice: t("proposal_matches.create.success")
    else
      redirect_back fallback_location: root_path, alert: @proposal_match.errors.full_messages.to_sentence
    end
  end

  def accept
    if @proposal_match.accept!
      Notification.add(@proposal_match.proposal.author, @proposal_match)

      # 2. PROVIDER ACCEPTS: Notify the Recipient (Proposal Author) to Confirm next
      Mailer.proposal_match_accepted(@proposal_match.id).deliver_later

      redirect_back fallback_location: root_path, notice: t("proposal_matches.accept.success")
    end
  end

  def confirm
    if @proposal_match.confirm!
      # Web notification to the provider
      Notification.add(@proposal_match.offer.author, @proposal_match)

      # 3. RECIPIENT CONFIRMS: Send introduction details to BOTH parties
      # This satisfies the requirement that both parties receive details upon connection
      Mailer.collaboration_introduction(@proposal_match.id, @proposal_match.proposal.author).deliver_later
      Mailer.collaboration_introduction(@proposal_match.id, @proposal_match.offer.author).deliver_later

      redirect_back fallback_location: root_path, notice: t("proposal_matches.confirm.success")
    end
  end

  def fulfill
    if @proposal_match.fulfill!
      Notification.add(@proposal_match.offer.author, @proposal_match)

      # 4. COMPLETED: Notify the Provider that the work has been marked fulfilled
      Mailer.proposal_match_confirmed(@proposal_match.id).deliver_later

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
