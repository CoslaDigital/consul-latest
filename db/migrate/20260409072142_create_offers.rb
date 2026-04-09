class CreateOffers < ActiveRecord::Migration[7.2]
  def change
    create_table :offers do |t|
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :geozone, foreign_key: true

      t.string :title, null: false, limit: 150
      t.text :description

      t.integer :status, default: 0, null: false

      t.datetime :hidden_at
      t.timestamps
    end
    add_index :offers, :status
    add_index :offers, :hidden_at
    add_index :offers, [:author_id, :hidden_at]
  end
end
