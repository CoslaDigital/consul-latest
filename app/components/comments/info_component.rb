class Comments::InfoComponent < ApplicationComponent
  attr_reader :comment, :valuation, :user_viewer

  def initialize(comment, valuation: false, user_viewer: nil)
    @comment = comment
    @valuation = valuation
    @user_viewer = user_viewer
  end

  def render?
    comment.present?
  end
end
