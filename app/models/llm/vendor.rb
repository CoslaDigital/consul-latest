class Llm::Vendor < ApplicationRecord
  validates :name, presence: true
#  validates :llm, presence: true, uniqueness: true, format: { with: /\A[a-zA-Z0-9\_]+\Z/ }
end
