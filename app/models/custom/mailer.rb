load Rails.root.join("app", "mailers", "mailer.rb")

class Mailer < ApplicationMailer
  # 1. User Notification (Kept separate, no BCC)
  def proposal_published(proposal)
    @proposal = proposal
    @email_to = @proposal.author.email
    @admin_email = ::Setting["admin_email"]
    with_user(@proposal.author) do
      mail(to: @email_to, subject: t("mailers.proposal_published.subject"))
    end
  end

  # 2. Admin Notification (New Method)
  def proposal_published_admin(proposal)
    @proposal = proposal
    @admin_email = ::Setting["admin_email"]

    # LOGGING 1: Check if the method was called and what the Setting returned
    Rails.logger.info "--- [Mailer Debug] Preparing Admin Email ---"
    Rails.logger.info "--- [Mailer Debug] Proposal ID: #{@proposal.id}"
    Rails.logger.info "--- [Mailer Debug] Target Admin Email: '#{@admin_email}'"

    # Stop if no admin email is configured
    if @admin_email.blank?
      Rails.logger.warn "--- [Mailer Debug] ABORTED: Admin email setting is blank or nil ---"
      return
    end

    with_user(@proposal.author) do
    mail(
      to: @admin_email,
      subject: "Consul Democracy: New Proposal Published - #{@proposal.title}"
    )
    end
    # LOGGING 2: Confirm the mail object was created
    Rails.logger.info "--- [Mailer Debug] Admin email object created successfully ---"
  end
end
