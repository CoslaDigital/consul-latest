class AddTsvToOffers < ActiveRecord::Migration[7.2]
  def change
    add_column :offers, :tsv, :tsvector

    add_index :offers, :tsv, using: :gin
  end
end
