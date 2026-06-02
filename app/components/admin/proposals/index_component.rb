class Admin::Proposals::IndexComponent < ApplicationComponent
  include Header

  attr_reader :proposals

  def initialize(proposals)
    @proposals = proposals
  end

  def title
    t("admin.proposals.index.title")
  end

  private

    def successful_proposals_link
      if Proposal.successful.any?
        link_to t("admin.questions.index.successful_proposals_tab"), successful_admin_proposals_path
      end
    end

    def proposal_kinds_link
      link_to "Manage Proposal Types", admin_proposal_kinds_path, class: "button hollow secondary float-right"
    end
end
