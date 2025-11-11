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
    # 1. FIND PROPOSALS (This was missing)
    # This logic finds, filters, and orders your proposals.
    # Your search/filter logic might be different, but this is the idea.
    @proposals = Proposal.all # Or whatever your base scope is
    
    # Example: Apply search if you have it
    if params[:search].present?
      @proposals = @proposals.where("title ILIKE ?", "%#{params[:search]}%")
    end
    
    # Apply ordering from your HasOrders module
#    @proposals = @proposals.order(order_options)
    
    # 2. CREATE PAGINATED VERSION FOR HTML
    # The view uses @proposals, so we must set it for the HTML case
    @paginated_proposals = @proposals.page(params[:page])

    # 3. RESPOND (This now includes HTML)
    respond_to do |format|
      format.html do
        # Pass the paginated list to the view
        @proposals = @paginated_proposals
        render :index
      end
      format.csv do
        # Pass the FULL, unpaginated list to the CSV generator
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
    # Define headers using your I18n translations
    headers = [
      t("admin.proposals.index.id"),
      Proposal.human_attribute_name(:title),
      t("proposals.form.proposal_summary"),
      Proposal.human_attribute_name(:description),
      t("admin.proposals.index.author"),
      Proposal.human_attribute_name(:responsible_name),
      t("attributes.email"),
      Proposal.human_attribute_name(:price),
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
          proposal.author.username,
          proposal.responsible_name,
          proposal.author.email,
          proposal.price,
          proposal.milestones.count,
          proposal.selected? 
        ]
      end
    end
  end
end
