class CreateLlmVendors < ActiveRecord::Migration[6.1]
  def change
    create_table :llm_vendors do |t|
      t.string :name
      t.text :description
      t.string :api_key
      t.text :script

      t.timestamps

      t.index :api_key
    end
  end
end