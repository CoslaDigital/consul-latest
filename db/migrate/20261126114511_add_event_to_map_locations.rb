class AddEventToMapLocations < ActiveRecord::Migration[8.0]
  def change
    add_reference :map_locations, :event, foreign_key: true
  end
end
