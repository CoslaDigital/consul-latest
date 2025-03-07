class Admin::Llm::Vendors::TableComponent < ApplicationComponent
  private

    def vendors
      ::Llm::Vendor.all
    end

    def attribute_name(attribute)
      ::Llm::Vendor.human_attribute_name(attribute)
    end
end