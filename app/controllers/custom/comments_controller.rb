load Rails.root.join("app", "controllers", "comments_controller.rb")
class CommentsController < ApplicationController
  include SettingsHelper
  include FlagActions

  before_action :authenticate_user!, only: [:create, :hide, :vote]
  before_action :load_commentable, only: :create
  before_action :verify_resident_for_commentable!, only: :create
  before_action :verify_comments_open!, only: [:create, :vote]
  before_action :build_comment, only: :create
  load_and_authorize_resource
  respond_to :html, :js

  def create
    if @comment.save
      CommentNotifier.new(comment: @comment).process
      add_notification @comment
      EvaluationCommentNotifier.new(comment: @comment).process if send_evaluation_notification?

      respond_with(@comment)
    else
      render :new
    end
  end

  def show
    @comment = Comment.find(params[:id])
    if @comment.valuation && @comment.author != current_user
      raise ActiveRecord::RecordNotFound
    else
    end
  end

  def vote
    @comment.vote_by(voter: current_user, vote: params[:value])
    respond_with @comment
  end

  def flag
    Flag.flag(current_user, @comment)
    render "shared/_refresh_flag_actions", locals: { flaggable: @comment, divider: true }
  end

  def unflag
    Flag.unflag(current_user, @comment)
    render "shared/_refresh_flag_actions", locals: { flaggable: @comment, divider: true }
  end

  def hide
    @comment.hide
  end

end
