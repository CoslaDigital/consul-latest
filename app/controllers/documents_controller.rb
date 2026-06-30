class DocumentsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :authenticate_user!, only: [:download], raise: false

  # 2. Skip automatic resource loading for download
  load_and_authorize_resource except: [:download]

  # 3. FIX: Explicitly tell CanCanCan "Do not check permissions for this action"
  skip_authorization_check only: [:download]

  def download
    document = Document.find(params[:id])

    # Redirect to the active_storage file
    redirect_to document.attachment, allow_other_host: true
  end

  def destroy
    respond_to do |format|
      format.html do
        if @document.destroy
          flash[:notice] = t "documents.actions.destroy.notice"
        else
          flash[:alert] = t "documents.actions.destroy.alert"
        end
        redirect_to request.referer
      end
      format.js do
        if @document.destroy
          flash.now[:notice] = t "documents.actions.destroy.notice"
        else
          flash.now[:alert] = t "documents.actions.destroy.alert"
        end
      end
    end
  end
end
