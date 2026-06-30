class AddOffersCountToTags < ActiveRecord::Migration[7.2]
  def change
    if table_exists?(:tags) && !column_exists?(:tags, :offers_count)
      add_column :tags, :offers_count, :integer, default: 0
    end
  end
end
