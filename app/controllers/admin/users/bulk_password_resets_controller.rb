class Admin::Users::BulkPasswordResetsController < Admin::BaseController
  authorize_resource class: "User"

  def index
    @batches = BulkPasswordReset.order(created_at: :desc).page(params[:page])
  end

  def show
    @batch = BulkPasswordReset.find(params[:id])
  end
end
