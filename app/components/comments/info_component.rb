class Comments::InfoComponent < ApplicationComponent
  attr_reader :comment, :valuation, :current_user

  def initialize(comment, valuation: false, current_user: nil)
    @comment = comment
    @valuation = valuation
    @current_user = current_user
  end

  def render?
    comment.present?
  end
end
