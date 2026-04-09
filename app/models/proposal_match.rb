class ProposalMatch < ApplicationRecord
  # Associations
  belongs_to :proposal # The Ask
  belongs_to :offer # The Resource

  # State Machine for the Match
  enum :status, { pending: 0, accepted: 10, rejected: 20, fulfilled: 30 }

  # Validations
  validates :proposal, presence: true
  validates :offer, presence: true
  # Prevent duplicate pending/active requests between the same two items
  validates :proposal_id, uniqueness: { scope: :offer_id, message: "has already requested this offer" }

  # Callbacks to handle timestamping based on state changes
  before_update :set_lifecycle_timestamps, if: :status_changed?

  private

    def set_lifecycle_timestamps
      if accepted? && accepted_at.nil?
        self.accepted_at = Time.current
      elsif fulfilled? && completed_at.nil?
        self.completed_at = Time.current

        # Optional: Automatically close the Offer if it's fully consumed
        offer.claimed!
      end
    end
end
