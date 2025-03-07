class Admin::Llm::Vendors::EditComponent < ApplicationComponent
  include Header

  attr_reader :vendor

  def initialize(vendor)
    @vendor = vendor
  end

  private

    def title
      t("admin.llm.vendors.edit.title")
    end
end