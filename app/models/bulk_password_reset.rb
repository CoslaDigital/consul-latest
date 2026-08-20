require 'csv'

class BulkPasswordReset < ApplicationRecord
  belongs_to :admin_user, class_name: "User"
  has_one_attached :credentials_file

  def process_resets!(user_ids)
    successful_rows = []
    users = User.where(id: user_ids)

    users.find_each do |user|
      new_password = User.random_password

      # Update silently to avoid validation hurdles
      if user.update(password: new_password, password_confirmation: new_password)
        successful_rows << [user.username, user.email, new_password]
        increment!(:success_count)
      end
    end

    csv_data = CSV.generate(headers: true) do |csv|
      csv << ["Username", "Email", "New Password"]
      successful_rows.each { |row| csv << row }
    end

    credentials_file.attach(
      io: StringIO.new(csv_data),
      filename: "bulk_resets_#{self.id}_#{Time.current.to_i}.csv",
      content_type: "text/csv"
    )

    update!(status: "completed")
  end
end
