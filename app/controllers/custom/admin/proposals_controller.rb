# app/controllers/custom/admin/proposals_controller.rb
load Rails.root.join("app", "controllers", "admin", "proposals_controller.rb")

class Admin::ProposalsController
  module ProjectTrackFiltering
    def index
      @proposals = Proposal.for_render
      @proposals = @proposals.search(@search_terms) if @search_terms.present?
      @proposals = @proposals.send("sort_by_#{@current_order}")

      if params[:project].present?
        kind = ProposalKind.find_by(slug: params[:project])

        @proposals = if kind
                       @proposals.where(proposal_kind_id: kind.id)
                     else
                       Proposal.none
                     end
      end

      respond_to do |format|
        format.html { @proposals = @proposals.page(params[:page]) }
        format.csv do
          send_data @proposals.to_csv,
                    filename: "proposals-#{Date.today}.csv"
        end
      end
    end
  end

  prepend ProjectTrackFiltering
end
