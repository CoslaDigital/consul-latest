load Rails.root.join("app", "controllers", "admin", "users_controller.rb")

class Admin::UsersController

  def index
    @users = User.all

    # 1. Handle the standard Consul "Search by name/email" logic
    if params[:search].present?
      @users = @users.where("username ILIKE :search OR email ILIKE :search OR document_number ILIKE :search", search: "%#{params[:search]}%")
    end

    # 2. Handle the standard Consul "Tabs" (All, Active, Erased)
    @current_filter = params[:filter] || "all"
    if @current_filter == "erased"
      @users = @users.where.not(erased_at: nil)
    elsif @current_filter == "active"
      @users = @users.where(erased_at: nil)
    else
      @users = @users.where(erased_at: nil) # Default to active users only
    end

    # 3. Add our Custom Geozone Filter
    if params[:geozone_id].present?
      @users = @users.where(geozone_id: params[:geozone_id])
    end

    # 4. Paginate for the view
    @users = @users.order(id: :desc).page(params[:page])
  end
  def new
    generated_password = User.random_password
    @user = User.new(password: generated_password)
  end

  def create
    @user = User.new(user_params)

    # Bypass standard registration hurdles
    @user.terms_of_service = "1"
    @user.confirmed_at = Time.current
    @user.verified_at = Time.current
    @user.residence_verified_at = Time.current

    # Safely handle users without email addresses
    if @user.email.blank?
      @user.newsletter = false
      @user.email_digest = false
      @user.email_on_direct_message = false
      @user.email_on_comment = false
      @user.email_on_comment_reply = false
    end

    if @user.save
      if user_params[:password].present?
        session[:new_password] = user_params[:password]
        redirect_to credentials_admin_user_path(@user)
      else
        redirect_to admin_users_path, notice: t("admin.users.create.notice", default: "User created successfully.")
      end
    else
      render :new
    end
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])

    if params[:user][:password].blank?
      params[:user].delete(:password)
    end

    if @user.update(user_params)
      if user_params[:password].present?
        session[:new_password] = user_params[:password]
        redirect_to credentials_admin_user_path(@user)
      else
        redirect_to admin_users_path, notice: t("admin.users.update.notice", default: "User updated successfully.")
      end
    else
      render :edit
    end
  end

  def credentials
    @user = User.find(params[:id])
    redirect_to admin_users_path if session[:new_password].blank?
  end

  def bulk_action
    user_ids = params[:user_ids]

    if user_ids.blank?
      redirect_to admin_users_path, alert: "No users selected."
      return
    end

    if params[:action_type] == "erase"
      # Background erase
      User.where(id: user_ids).each { |u| u.delay.erase }
      redirect_to admin_users_path, notice: "Selected users are being erased in the background."

    elsif params[:action_type] == "reset_password"
      # Background password reset with CSV tracking
      batch = BulkPasswordReset.create!(
        admin_user: current_user,
        target_count: user_ids.count
      )
      batch.delay.process_resets!(user_ids)

      redirect_to admin_users_bulk_password_reset_path(batch), notice: "Password reset started."
    else
      redirect_to admin_users_path, alert: "Invalid action."
    end
  end

  private

    def user_params
      p = params.require(:user).permit(:username, :email, :password)

      # 1. Force empty strings to nil to avoid PostgreSQL Unique Index crashes
      p[:email] = nil if p[:email].blank?

      # 2. Silently duplicate the password to satisfy Devise validations
      p[:password_confirmation] = p[:password] if p[:password].present?

      p
    end
end
