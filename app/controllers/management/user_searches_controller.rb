class Management::UserSearchesController < Management::BaseController
  def index
    @users = if params[:search].present?
               User.where("email ILIKE :search OR username ILIKE :search", search: "%#{params[:search]}%")
             else
               User.none
             end
  end

  def create
    session[:document_type] = nil
    session[:document_number] = nil
    session[:managed_user_id] = params[:user_id]
    clear_password

    redirect_to management_root_path, notice: t("management.sessions.now_managing_user", default: "Now managing user.")
  end
end
