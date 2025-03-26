class Llm::Vendor < ApplicationRecord
  validates :name, presence: true
#  validates :llm, presence: true, uniqueness: true, format: { with: /\A[a-zA-Z0-9\_]+\Z/ }
  def self.supported_vendors
    [
      Vendor.new(1, "OpenAI"),
      Vendor.new(2, "Moderation API"),
      Vendor.new(3, "Deepseek-WIP")
      # Add more vendors as needed
    ]
  end

end
