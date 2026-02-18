# frozen_string_literal: true

class ConnectionAudit < ApplicationRecord
  belongs_to :auditable, polymorphic: true

  # Geocoder setup
  geocoded_by :ip_address
  after_validation :geocode, if: ->(obj) { obj.ip_address.present? }

  # Handy scope for your reporting
  scope :suspicious, -> { where(suspicious: true) }
  scope :voters_by_location, -> {
    group(:city, :country_code, :suspicious).distinct.count(:auditable_id)
  }
  # app/models/connection_audit.rb
  def self.combined_participation_stats(precision = 2)
    p = precision.to_i

    select(
      "city",
      "country_code",
      "MAX(suspicious::int)::boolean as suspicious",
      "MAX(failure_reason) as failure_reason",
      "ROUND(latitude::numeric, #{p}) as lat_cluster",
      "ROUND(longitude::numeric, #{p}) as lng_cluster",
      "COUNT(DISTINCT auditable_id) as voter_count"
    )
    # CRITICAL: Group by the actual function, not the 'lat_cluster' alias
      .group("city", "country_code", "ROUND(latitude::numeric, #{p})", "ROUND(longitude::numeric, #{p})")
      .order("voter_count DESC")
  end

  def self.participation_clusters(precision = 2)
    # precision 1: ~11km (District)
    # precision 2: ~1.1km (Neighborhood)
    # precision 3: ~110m (Street)
    select(
      "ROUND(latitude::numeric, #{precision.to_i}) as lat_cluster",
      "ROUND(longitude::numeric, #{precision.to_i}) as lng_cluster",
      "COUNT(DISTINCT auditable_id) as voter_count"
    )
      .group("lat_cluster, lng_cluster")
      .order("voter_count DESC")
  end
end
