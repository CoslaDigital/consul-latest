class Shared::BasicAuthorInfoComponent < ApplicationComponent
  attr_reader :author, :show_organization, :user_viewer
  alias_method :show_organization?, :show_organization

  def initialize(author, show_organization: true, user_viewer: nil)
    @author = author
    @show_organization = show_organization
    @user_viewer = user_viewer
  end

  def show_real_name?
    !target_for_masking? || official_account? || viewer_can_see_real_name?
  end

  private

    def target_for_masking?
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
