class AddOffersCountToTags < ActiveRecord::Migration[7.2]
  def change
    add_column :tags, :offers_count, :integer
  end
end
