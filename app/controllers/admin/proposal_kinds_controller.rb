# app/controllers/admin/proposal_kinds_controller.rb
class Admin::ProposalKindsController < Admin::BaseController
  before_action :set_proposal_kind, only: [:edit, :update, :destroy, :set_default]

  def index
    @proposal_kinds = ProposalKind.order(default: :desc, name: :asc)
  end

  def new
    @proposal_kind = ProposalKind.new
  end

  def edit
  end

  def create
    @proposal_kind = ProposalKind.new(proposal_kind_params)
    @proposal_kind.default = true if ProposalKind.count.zero?

    if @proposal_kind.save
      redirect_to admin_proposal_kinds_path, notice: t("flash.actions.create.proposal_kind", default: "Proposal type successfully created.")
    else
      render :new
    end
  end

  def update
    if @proposal_kind.update(proposal_kind_params)
      redirect_to admin_proposal_kinds_path, notice: t("flash.actions.update.proposal_kind", default: "Proposal type successfully updated.")
    else
      render :edit
    end
  end

  def destroy
    if @proposal_kind.default?
      redirect_to admin_proposal_kinds_path, alert: "You cannot delete the system default proposal type."
    else
      @proposal_kind.destroy
      redirect_to admin_proposal_kinds_path, notice: t("flash.actions.destroy.proposal_kind", default: "Proposal type successfully removed.")
    end
  end

  def set_default
    @proposal_kind.update!(default: true)
    redirect_to admin_proposal_kinds_path, notice: "#{@proposal_kind.name} set as system default choice."
  end

  private

    def set_proposal_kind
      @proposal_kind = ProposalKind.find(params[:id])
    end

    def proposal_kind_params
      params.require(:proposal_kind).permit(:name, :default, :color, :icon)
    end
end
