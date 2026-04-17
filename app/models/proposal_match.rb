class ProposalMatch < ApplicationRecord
  include Notifiable

  belongs_to :proposal
  belongs_to :offer

  # Status Lifecycle
  enum :status, { pending: 0, accepted: 10, confirmed: 20, fulfilled: 30, rejected: 40 }

  validates :proposal_id, uniqueness: { scope: :offer_id, message: "Collaboration already requested" }

  # Explicit lifecycle methods (The "Proposal#publish" approach)

  def accept!
    transaction do
      update!(status: :accepted, accepted_at: Time.current)
      offer.pending! # Move parent offer to pending to hide it from others
      Mailer.proposal_match_accepted(self).deliver_later
    end
  rescue ActiveRecord::RecordInvalid
    false
  end

  def confirm!
    transaction do
      update!(status: :confirmed, confirmed_at: Time.current)
      Mailer.proposal_match_confirmed(self).deliver_later
    end
  rescue ActiveRecord::RecordInvalid
    false
  end

  def fulfill!
    transaction do
      update!(status: :fulfilled, completed_at: Time.current)
      # Logic: if this was the last active match, we might leave offer as is,
      # or provide a prompt to the user to mark the Offer as 'Claimed'.
    end
  rescue ActiveRecord::RecordInvalid
    false
  end

  def notify_admin(action_type)
    Mailer.proposal_match_admin_notification(self, action_type).deliver_later
  end

  def reject!
    update(status: :rejected, rejected_at: Time.current)
  end
end
