class Shared::DetailedAuthorInfoComponent < ApplicationComponent
  attr_reader :author, :user_viewer

  def initialize(author, user_viewer: nil)
    @author = author
    @user_viewer = user_viewer
  end

  def show_real_name?
    # 1. Always show the real name if they are a regular user without "consul.dev"
    # 2. If they DO have "consul.dev", only show real name to officials/admins/themselves
    !target_for_masking? || official_account? || viewer_can_see_real_name?
  end

  private

  private

    def target_for_masking?
      # Uses the User model's class method to verify if it's a YS Card
      User.valid_ys_document?(author.username)
    end

    def official_account?
      author.administrator? || author.moderator? || author.official_level.to_i > 0
    end

    def viewer_can_see_real_name?
      viewer = user_viewer || helpers.current_user
      viewer&.administrator? || viewer&.id == author.id
    end
end
