class CreateOffers < ActiveRecord::Migration[7.2]
  def change
    unless table_exists?(:offers)
      create_table :offers do |t|
        t.references :author, null: false, foreign_key: { to_table: :users }
        t.references :geozone, foreign_key: true

        t.string :title, null: false, limit: 150
        t.text :description

        t.integer :status, default: 0, null: false
        t.integer :comments_count, default: 0

        t.tsvector :tsv

        t.datetime :hidden_at
        t.timestamps
      end
    end

    # Safety checks for columns if table already existed from a partial migration
    add_column :offers, :comments_count, :integer, default: 0 unless column_exists?(:offers, :comments_count)
    add_column :offers, :tsv, :tsvector unless column_exists?(:offers, :tsv)

    # Safety checks for indexes
    add_index :offers, :status unless index_exists?(:offers, :status)
    add_index :offers, :hidden_at unless index_exists?(:offers, :hidden_at)
    add_index :offers, [:author_id, :hidden_at] unless index_exists?(:offers, [:author_id, :hidden_at])
    add_index :offers, :tsv, using: :gin unless index_exists?(:offers, :tsv)
  end
end
