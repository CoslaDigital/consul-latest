class Llm::Vendor < ApplicationRecord
  validates :name, presence: true
#  validates :llm, presence: true, uniqueness: true, format: { with: /\A[a-zA-Z0-9\_]+\Z/ }
  def self.supported_vendors
    [
      Vendor.new(1, "OpenAI"),
      Vendor.new(2, "Vendor2"),
      Vendor.new(3, "Vendor3")
      # Add more vendors as needed
    ]
  end

end
