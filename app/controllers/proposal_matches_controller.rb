class ProposalMatchesController < ApplicationController
  before_action :authenticate_user!

  def create
    @match = ProposalMatch.new(match_params)
    @proposal = Proposal.find(match_params[:proposal_id])
    @offer = Offer.find(match_params[:offer_id])

    # Security Check: The user must own EITHER the Proposal or the Offer to initiate a match.
    unless @proposal.author == current_user || @offer.author == current_user
      return redirect_back fallback_location: root_path, alert: "You must own one of these items to request a collaboration."
    end

    if @match.save
      # Determine who to notify based on who initiated the request
      if @proposal.author == current_user
        # The Asker initiated. Notify the Provider.
        notify_provider(@match)
        notice_message = "Collaboration request sent to the provider!"
      else
        # The Provider initiated. Notify the Asker.
        notify_asker(@match)
        notice_message = "Your offer has been sent to the proposal author!"
      end

      redirect_back fallback_location: root_path, notice: notice_message
    else
      redirect_back fallback_location: root_path, alert: "Could not send request: #{@match.errors.full_messages.to_sentence}"
    end
  end

  private

    def match_params
      params.require(:proposal_match).permit(:proposal_id, :offer_id)
    end

    # Placeholders for your Consul Notification logic
    def notify_provider(match)
      # Notification.add(match.offer.author, ...)
    end

    def notify_asker(match)
      # Notification.add(match.proposal.author, ...)
    end
end
