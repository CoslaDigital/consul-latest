class Admin::Llm::Vendors::NewComponent < ApplicationComponent
  include Header

  attr_reader :vendor

  def initialize(vendor)
    @vendor = vendor
  end

  private

    def title
      t("admin.llm.vendors.new.title")
    end
end