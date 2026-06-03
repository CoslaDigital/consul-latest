# app/controllers/admin/legislation/propositions_imports_controller.rb
class Admin::Legislation::PropositionsImportsController < Admin::Legislation::BaseController
  load_and_authorize_resource class: "Legislation::PropositionsImport"

  def create
    @import = Legislation::PropositionsImport.new(propositions_import_params)

    # Pass current administrative user to manage ownership validation
    if @import.save(current_user)
      redirect_to admin_legislation_processes_path,
                  notice: "Jigsaw matrix imported successfully! Created #{@import.created_questions.count} questions under a brand new Draft Process."
    else
      render :new
    end
  end

  def new
    # Ensure the variable name matches exactly with the layout reference!
    @import = Legislation::PropositionsImport.new
  end

  private

    def propositions_import_params
      return {} if params[:legislation_propositions_import].blank?

      params.require(:legislation_propositions_import).permit(:file)
    end
end
