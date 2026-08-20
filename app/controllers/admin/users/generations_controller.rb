class Admin::Users::GenerationsController < Admin::BaseController
  authorize_resource class: "User"

  def new
    @geozones = Geozone.all.order(:name)
  end

  def create
    batch = UserGenerationBatch.create!(
      admin_user: current_user,
      target_count: params[:number].to_i,
      status: "processing"
    )

    # MAGIC HAPPENS HERE: Adding .delay pushes it to the background queue
    batch.delay.process_generation!(
      params[:prefix].presence || "demo",
      params[:geozone_id],
      params[:password_type]
    )

    redirect_to admin_users_generation_path(batch),
                notice: t("admin.users.generations.started", default: "Batch generation started. This may take a few minutes.")
  end

  def show
    @batch = UserGenerationBatch.find(params[:id])
  end
end
