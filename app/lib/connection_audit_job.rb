class ConnectionAuditJob < Struct.new(:auditable_type, :auditable_id, :ip, :user_agent)
  def perform
    auditable = auditable_type.constantize.find_by(id: auditable_id)
    return unless auditable

    # 1. Fetch Tenant Secrets
    secrets = Tenant.current_secrets.dig(:apis) || {}
    provider = secrets[:geocoder_provider]&.to_sym || :ipinfo_io
    api_key = secrets[:geocoder_api_key]
    max_dist = secrets[:geocoder_max_distance_km] || 50

    audit = auditable.connection_audits.new(
      ip_address: ip,
      raw_metadata: { user_agent: user_agent }
    )

    # 2. Manual Geocoding (Explicit assignment)
    begin
      Geocoder.configure(ip_lookup: provider, api_key: api_key, timeout: 15) if api_key.present?

      result = Geocoder.search(ip).first

      if result
        audit.city = result.city
        audit.country_code = result.country_code
        audit.latitude = result.latitude
        audit.longitude = result.longitude
      else
        audit.failure_reason = "No geocoding results found for IP"
      end
    rescue => e
      audit.failure_reason = "Geocoding error: #{e.message}"
    end

    # 3. Rule Evaluation
    if audit.latitude && audit.longitude
      # A. Geozone Check
      zones = Array(auditable.try(:budget)&.geozones || auditable.try(:heading)&.geozone).compact
      zones_with_boundaries = zones.select { |z| z.html_geometry.present? }

      if zones_with_boundaries.any?
        is_inside = zones_with_boundaries.any? { |z| z.contains_coordinate?(audit.latitude, audit.longitude) }
        unless is_inside
          audit.suspicious = true
          audit.failure_reason = "Outside GeoJSON boundary: #{zones_with_boundaries.map(&:name).join(', ')}"
        end
      else
        # B. Distance Fallback
        city_lat = Setting["map.latitude"]
        city_lng = Setting["map.longitude"]

        if city_lat.present? && city_lng.present?
          distance = Geocoder::Calculations.distance_between(
            [audit.latitude, audit.longitude],
            [city_lat, city_lng],
            units: :km
          )

          if distance > max_dist.to_f
            audit.suspicious = true
            audit.failure_reason = "Distance: #{distance.round(2)}km from city center"
          end
        end
      end
    end

    # 4. Final Save
    audit.save!
  end
end
