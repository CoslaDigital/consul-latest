class Admin::UsersController < Admin::BaseController
  load_and_authorize_resource class: User

  has_filters %w[active erased], only: :index

  def index
    @users = @users.send(@current_filter)
    @users = @users.by_username_email_or_document_number(params[:search]) if params[:search]
    @users = @users.page(params[:page])
    respond_to do |format|
      format.html
      format.js
    end
  end

  def lock
    @user.lock_access!
    redirect_to admin_users_path, notice: t("admin.users.lock.success")
  end

  def unlock
    @user.unlock_access!
    redirect_to admin_users_path, notice: t("admin.users.unlock.success")
  end
end
