class UserGenerationBatch < ApplicationRecord
  belongs_to :admin_user, class_name: "User"

  # This relies on ActiveStorage to securely hold the CSV
  has_one_attached :credentials_file
end
