class Admin::Llm::Vendors::FormComponent < ApplicationComponent
  attr_reader :vendor

  def initialize(vendor)
    @vendor = vendor
  end
end