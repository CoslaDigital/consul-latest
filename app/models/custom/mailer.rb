load Rails.root.join("app", "mailers", "mailer.rb")

class Mailer < ApplicationMailer
  # 1. User Notification (Kept separate, no BCC)
  def proposal_published(proposal)
    @proposal = proposal
    @email_to = @proposal.author.email

    with_user(@proposal.author) do
      mail(to: @email_to, subject: t("mailers.proposal_published.subject"))
    end
  end

  # 2. Admin Notification (New Method)
  def proposal_published_admin(proposal)
    @proposal = proposal
    @admin_email = ::Setting["admin_email"]

    # Stop if no admin email is configured
    return unless @admin_email.present?

    mail(
      to: @admin_email,
      subject: "Consul Democracy: New Proposal Published - #{@proposal.title}"
    )
  end
end
