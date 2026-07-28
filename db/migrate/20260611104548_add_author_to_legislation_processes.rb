class AddAuthorToLegislationProcesses < ActiveRecord::Migration[7.2]
  def change
    add_column :legislation_processes, :author_id, :integer
    add_index :legislation_processes, :author_id
  end
end
