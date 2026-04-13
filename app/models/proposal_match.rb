class ProposalMatch < ApplicationRecord
  # Associations
  belongs_to :proposal # The Ask
  belongs_to :offer # The Resource

  # State Machine for the Match
  enum :status, {
    pending: 0,
    accepted: 10,
    confirmed: 15,
    rejected: 20,
    withdrawn: 25,
    fulfilled: 30
  }, default: :pending

  scope :confirmed, -> { where(status: :confirmed) }
  scope :pending, -> { where(status: :pending) }
  scope :fulfilled, -> { where(status: :fulfilled) }

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
      elsif confirmed? && confirmed_at.nil?
        self.confirmed_at = Time.current
      elsif fulfilled? && completed_at.nil?
        self.completed_at = Time.current

        # We update the OFFER to 'claimed' because this specific
        # MATCH has been 'fulfilled'.
        offer.update(status: :claimed)
      end
    end
end
