class CreateConnectionAudits < ActiveRecord::Migration[7.0]
  def change
    create_table :connection_audits do |t|
      # This handles the polymorphic link (e.g., to Budget::Ballot or User)
      t.references :auditable, polymorphic: true, index: true

      # Using 'inet' for optimized IP storage (PostgreSQL specific)
      t.inet :ip_address

      # Geolocation metadata fields
      t.string :country_code
      t.string :city
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6

      # Flagging and Audit Info
      t.boolean :suspicious, default: false
      t.string :failure_reason # Why it was flagged (e.g., "Outside geofence")

      # Store extra data from geocoder for future-proofing
      t.jsonb :raw_metadata, default: {}

      t.timestamps
    end

    # Optional: Index on ip_address for faster lookup of multiple votes from one IP
    add_index :connection_audits, :ip_address
  end
end
