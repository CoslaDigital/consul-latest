class Admin::Users::BulkPasswordResetsController < Admin::BaseController
  authorize_resource class: "User"

  def show
    @batch = BulkPasswordReset.find(params[:id])
  end
end
