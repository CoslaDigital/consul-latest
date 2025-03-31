class AddModerationFieldsToComments < ActiveRecord::Migration[7.0]
  def change
    add_column :comments, :moderated_at, :datetime
    add_column :comments, :moderation_reason, :string
  end
end
