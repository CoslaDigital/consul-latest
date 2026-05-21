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

      results = moderate
      if results[:flagged] || results[:hidden]
        flash[:error] = "Your comment is being moderated. Please come back later."
        # returning here prevents execution from slipping down to the JS render
        return redirect_back(fallback_location: root_path)
      end

      # Explicitly handle standard, non-moderated JS and HTML responses
      respond_to do |format|
        format.html { redirect_back(fallback_location: root_path) }
        format.js { render :create } # Tethers explicitly to your create.js.erb
      end
    else
      respond_to do |format|
        format.html { render :new }
        format.js { render :new }
      end
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

def openaimoderate(text_string)
  thresh = Rails.application.secrets.openai_thresh || 1.5
  openai_key = Rails.application.secrets.openai_key
  is_hidden = false
  is_flagged = false
  flag_score = 0
  flag_cat = ""
  puts "openaikey is #{openai_key}"

  if openai_key.nil? || openai_key.strip.empty?
    return { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: "missing api key" }
  end

  client = OpenAI::Client.new(access_token: openai_key)
  body = text_string
  response = client.moderations(parameters: { input: body })
  is_hidden = response["results"][0]["flagged"] == true ? true : false
  scores = response["results"][0]["category_scores"]
  puts scores
  total_score = 0

  scores.each do |cat, score|
    total_score += score
    if score > thresh
      flag_score += 2
      flag_cat += cat
    end
  end
  if flag_score > thresh
     is_flagged = true
  end
  return { hidden: is_hidden, flagged: is_flagged, flags: flag_score, category: flag_cat }
end

 def moderate
   # setup
    is_flagged = false
    is_hidden = false
    flag_score = 0
    flag_cat = ""

    if feature?(:cosla)
      puts "going to do it"
    end

    thresh = Rails.application.secrets.openai_thresh || 1.5
    openai_key = Rails.application.secrets.openai_key

    body = @comment.body

    #test code to avoid using openai
    if body == "Bad Bad Bad Comment"
      is_flagged = "true"
      total_score = 300
      flag_score = 300
    elsif openai_key && !openai_key.strip.empty?
       response = openaimoderate(body)
       is_hidden = response[:hidden]
       is_flagged = response[:flagged]
       flag_score = response[:flags] || 0
    end

   if is_flagged
         @comment.flags_count = flag_score
         @comment.save
    end
    if is_hidden || (flag_score > thresh)
        @comment.hidden_at = Time.current
        @comment.save
     end
 return { hidden: is_hidden, flagged: is_flagged }

 end


end
