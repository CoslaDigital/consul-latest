class Admin::ProposalsController < Admin::BaseController
  require 'csv'
  include ActionView::Helpers::SanitizeHelper
  include HasOrders
  include CommentableActions
  include FeatureFlags
  feature_flag :proposals

  has_orders %w[created_at]

  before_action :load_proposal, except: [:index, :successful]
  
  
  def index
    @proposals = Proposal.all 
    
    if params[:search].present?
      @proposals = @proposals.where("title ILIKE ?", "%#{params[:search]}%")
    end
    
    @paginated_proposals = @proposals.page(params[:page])

    respond_to do |format|
      format.html do
        @proposals = @paginated_proposals
        render :index
      end
      format.csv do
        csv_data = generate_csv(@proposals)
        send_data csv_data, filename: "proposals-#{Date.today}.csv"
      end
    end
  end
    
  def successful
    @proposals = Proposal.successful.sort_by_confidence_score
  end

  def show
  end

  def update
    if @proposal.update(proposal_params)
      redirect_to admin_proposal_path(@proposal), notice: t("admin.proposals.update.notice")
    else
      render :show
    end
  end

  def select
    @proposal.update!(selected: true)

    respond_to do |format|
      format.html { redirect_to request.referer, notice: t("flash.actions.update.proposal") }
      format.js { render :toggle_selection }
    end
  end

  def deselect
    @proposal.update!(selected: false)

    respond_to do |format|
      format.html { redirect_to request.referer, notice: t("flash.actions.update.proposal") }
      format.js { render :toggle_selection }
    end
  end

  private

    def resource_model
      Proposal
    end

    def load_proposal
      @proposal = Proposal.find(params[:id])
    end

    def proposal_params
      params.require(:proposal).permit(allowed_params)
    end

    def allowed_params
      [:selected]
    end
    
    def generate_csv(proposals)
    headers = [
      t("admin.proposals.index.id"),
      Proposal.human_attribute_name(:title),
      t("proposals.form.proposal_summary"),
      Proposal.human_attribute_name(:description),
      Proposal.human_attribute_name(:price),
      t("admin.proposals.index.author"),
      Proposal.human_attribute_name(:responsible_name),
      t("attributes.email"),
      t("proposals.form.geozone"),
      t("admin.proposals.index.milestones"),
      t("admin.proposals.index.selected")
    ]

    CSV.generate(headers: true) do |csv|
     csv << headers

      proposals.each do |proposal|
        clean_summary = strip_tags(proposal.summary).gsub(/\s+/, ' ').strip
        clean_description = strip_tags(proposal.description).gsub(/\s+/, ' ').strip
        csv << [
          proposal.id,
          proposal.title,
          strip_tags(proposal.summary),
          strip_tags(proposal.description),
          proposal.price,
          proposal.author.username,
          proposal.responsible_name,
          proposal.author.email,
          proposal.geozone&.name,
          proposal.milestones.count,
          proposal.selected? 
        ]
      end
    end
  end
end
