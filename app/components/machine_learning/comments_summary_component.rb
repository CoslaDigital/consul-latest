class MachineLearning::CommentsSummaryComponent < ApplicationComponent
  attr_reader :commentable

  def initialize(commentable)
    @commentable = commentable
  end

  def render?
    MachineLearning.enabled? && Setting["machine_learning.comments_summary"].present? && body.present?
  end

  private

    def body
      commentable.summary_comment&.body
    end

  def sentiment
    @sentiment ||= commentable.summary_comment&.sentiment_analysis || {}
  end

  # NEW: Check if we have valid data to show
  def sentiment_present?
    return false if sentiment.blank?

    # Ensure we have at least some data (sum > 0)
    (sentiment['positive'].to_i + sentiment['negative'].to_i + sentiment['neutral'].to_i) > 0
  end

end
