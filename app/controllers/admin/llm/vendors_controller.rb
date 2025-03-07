class Admin::Llm::VendorsController < Admin::BaseController
  load_and_authorize_resource :vendor, class: "::Llm::Vendor"

  def create
    if @vendor.save
      redirect_to admin_settings_path(anchor: "tab-llm-consent"),
                  notice: t("admin.llm.vendors.create.notice")
    else
      render :new
    end
  end

  def update
    if @vendor.update(vendor_params)
      redirect_to admin_settings_path(anchor: "tab-llm-consent"),
                  notice: t("admin.llm.vendors.update.notice")
    else
      render :edit
    end
  end

  def destroy
    @vendor.destroy!

    redirect_to admin_settings_path(anchor: "tab-llm-consent"),
                notice: t("admin.llm.vendors.destroy.notice")
  end

  private

    def vendor_params
      params.require(:llm_vendor).permit(allowed_params)
    end

    def allowed_params
      [:name, :description, :api_key, :script]
    end
end