class ProposalMatchesController < ApplicationController
  before_action :authenticate_user!

  # This handles @proposal_match = ProposalMatch.new(match_params)
  # AND checks the 'can :create, ProposalMatch' ability automatically.
  load_and_authorize_resource

  def create
    # We use the auto-loaded @proposal_match from CanCanCan
    if @proposal_match.save
      send_notification(@proposal_match)

      notice_message = if @proposal_match.proposal.author == current_user
                         t("proposal_matches.create.sent_to_provider", default: "Collaboration request sent to the provider!")
                       else
                         t("proposal_matches.create.sent_to_asker", default: "Your offer has been sent to the proposal author!")
                       end

      redirect_back fallback_location: root_path, notice: notice_message
    else
      redirect_back fallback_location: root_path, alert: @proposal_match.errors.full_messages.to_sentence
    end
  end

  def accept
    # Start a transaction to ensure both updates happen together
    Offer.transaction do
      if @proposal_match.update(status: :accepted, accepted_at: Time.current)
        # Automatically move the Offer to 'pending' status
        @proposal_match.offer.update!(status: :pending)

        Notification.add(@proposal_match.proposal.author, @proposal_match)

        redirect_back fallback_location: root_path,
                      notice: t("proposal_matches.accept.success", default: "Collaboration confirmed! The offer is now marked as 'Pending'.")
      end
    end
  end

  def reject
    if @proposal_match.update(status: :rejected)
      redirect_back fallback_location: root_path, notice: t("proposal_matches.reject.success", default: "Match declined.")
    end
  end

  private

    def proposal_match_params
      params.require(:proposal_match).permit(:proposal_id, :offer_id)
    end

    def send_notification(match)
      # Determine recipient: if I own the proposal, notify the offer author (and vice versa)
      recipient = (match.proposal.author == current_user) ? match.offer.author : match.proposal.author

      # Using Consul's native Notification system
      # You'll eventually need to define this in en.yml under 'notifications.proposal_match_created'
      Notification.add(recipient, match) if recipient
    end
end
