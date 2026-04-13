class AddCommentsCountToOffers < ActiveRecord::Migration[7.2]
  def change
    add_column :offers, :comments_count, :integer, default: 0
  end
end
