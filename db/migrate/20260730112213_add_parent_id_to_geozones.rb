class AddParentIdToGeozones < ActiveRecord::Migration[7.2]
  def change
    add_reference :geozones, :parent, foreign_key: { to_table: :geozones }, index: true
  end
end
