class ConnectionAuditJob < Struct.new(:auditable_type, :auditable_id, :ip, :user_agent)
  def perform
    auditable = auditable_type.constantize.find_by(id: auditable_id)
    return unless auditable

    # 1. Fetch Tenant Secrets (Hybrid lookup to handle flat or nested structure)
    all_secrets = Tenant.current_secrets
    api_config = all_secrets.dig(:apis) || {}

    provider = api_config[:geocoder_provider]&.to_sym || all_secrets[:geocoder_provider]&.to_sym || :ipinfo_io
    api_key = api_config[:geocoder_api_key] || all_secrets[:geocoder_api_key]
    max_dist = api_config[:geocoder_max_distance_km] || all_secrets[:geocoder_max_distance_km] || 50

    audit = auditable.connection_audits.new(
      ip_address: ip,
      raw_metadata: { user_agent: user_agent }
    )

    # 2. Manual Geocoding (Thread-safe direct parameters)
    begin
      # We pass options directly to .search to bypass global config issues
      search_options = {
        ip_lookup: provider,
        timeout: 15,
        skip_cache: true
      }
      search_options[:api_key] = api_key if api_key.present?

      result = Geocoder.search(ip, search_options).first

      if result
        audit.city = result.city
        audit.country_code = result.country_code
        audit.latitude = result.latitude
        audit.longitude = result.longitude

        # Log if we hit the "London Snap" default coordinate
        if audit.latitude.to_f == 51.5085 && audit.longitude.to_f == -0.1257
          audit.raw_metadata[:geocoding_note] = "ISP Default (London Center)"
        end
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

          # If it's a "London Snap" default, we might want to be more lenient,
          # but for now, we follow your max_dist rule.
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
