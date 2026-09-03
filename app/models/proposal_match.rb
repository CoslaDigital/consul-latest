class ProposalMatch < ApplicationRecord
  include Notifiable

  belongs_to :proposal
  belongs_to :offer

  # Status Lifecycle
  enum :status, { pending: 0, accepted: 10, confirmed: 20, fulfilled: 30, rejected: 40 }

  validates :proposal_id, uniqueness: { scope: :offer_id, message: "Collaboration already requested" }

  # Milestone automation
  after_commit :create_proposal_milestone, on: [:create, :update]

  def accept!
    transaction do
      update!(status: :accepted, accepted_at: Time.current)
      offer.pending! # Move parent offer to pending to hide it from others
    end
  rescue ActiveRecord::RecordInvalid
    false
  end

  def confirm!
    transaction do
      update!(status: :confirmed, confirmed_at: Time.current)
    end
  rescue ActiveRecord::RecordInvalid
    false
  end

  def fulfill!
    transaction do
      update!(status: :fulfilled, completed_at: Time.current)
    end
  rescue ActiveRecord::RecordInvalid
    false
  end

  def reject!
    update!(status: :rejected, rejected_at: Time.current)
  end

  def notify_admin(action_type)
    Mailer.proposal_match_admin_notification(self, action_type).deliver_later
  end

  def notifiable_title
    proposal.title
  end

  def notifiable_body
    I18n.t("collaborations.notifications.new_match_body",
           offer_title: offer.title)
  end

  def human_name
    proposal.title
  end

  private

    def create_proposal_milestone
      status_name, title_key, desc_key = milestone_config_for_status

      return unless status_name

      milestone_status = Milestone::Status.find_or_create_by!(name: status_name)

      return if proposal.milestones.exists?(status_id: milestone_status.id, description: I18n.t(desc_key, resource_title: offer.title))

      proposal.milestones.create!(
        status: milestone_status,
        publication_date: Date.current,
        title: I18n.t(title_key, resource_title: offer.title.truncate(30), default: "Project Update: #{status_name}"),
        description: I18n.t(desc_key, resource_title: offer.title, user_name: offer.author.name, default: "Collaboration reached phase: #{status_name}")
      )
    end

    def milestone_config_for_status
      case status
      when "pending"
        ["Mutual Aid Requested", "proposals.milestones.requested.title", "proposals.milestones.requested.description"]
      when "accepted"
        ["Mutual Aid Pre-Accepted", "proposals.milestones.accepted.title", "proposals.milestones.accepted.description"]
      when "confirmed"
        ["Mutual Aid In Progress", "proposals.milestones.confirmed.title", "proposals.milestones.confirmed.description"]
      when "fulfilled"
        ["Mutual Aid Completed", "proposals.milestones.fulfilled.title", "proposals.milestones.fulfilled.description"]
      else
        nil
      end
    end
end
