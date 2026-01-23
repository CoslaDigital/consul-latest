class AddVisibillityToDocuments < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :visibility, :integer, default: 0
    add_index :documents, :visibility
  end
end
