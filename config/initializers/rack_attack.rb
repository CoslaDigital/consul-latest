# config/initializers/rack_attack.rb
require "maxmind/db"

class Rack::Attack
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new(size: 32.megabytes)

  GEOIP_PATH = Rails.root.join("db", "geoip", "GeoLite2-Country.mmdb")
  GEOIP_DB = File.exist?(GEOIP_PATH) ? MaxMind::DB.new(GEOIP_PATH.to_s, mode: MaxMind::DB::MODE_MEMORY) : nil

  def self.client_ip(req)
    if Rails.env.development? || Rails.env.test?
      forwarded = req.get_header("HTTP_X_FORWARDED_FOR")
      return forwarded.split(",").first.strip if forwarded.present?
    end

    req.get_header("action_dispatch.remote_ip")&.to_s || req.ip
  end

  safelist("allow-internal-ips") do |req|
    ip = client_ip(req)
    (ip == "127.0.0.1" || ip == "::1") && (Rails.env.production? || req.get_header("HTTP_X_FORWARDED_FOR").blank?)
  end

  # Geofence Rule
  blocklist("geofence-ys-login") do |req|
    is_ys_login = (req.path == "/ys_login" || req.path == "/ys_login/") && req.post?

    # Clean delegation to the Setting model
    if is_ys_login && Setting.geofence_card_login_enabled? && GEOIP_DB
      ip = client_ip(req)
      record = GEOIP_DB.get(ip)
      country_code = record&.dig("country", "iso_code")

      country_code.present? && !Setting.geofence_allowed_countries.include?(country_code)
    else
      false
    end
  end

  # Throttle: Max 10 login submissions per minute per IP
  throttle("limit-ys-login-attempts", limit: 10, period: 1.minute) do |req|
    if (req.path == "/ys_login" || req.path == "/ys_login/") && req.post?
      client_ip(req)
    end
  end

  # Blanket DoS Throttle
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    client_ip(req) unless req.path.start_with?("/assets", "/packs", "/vite")
  end

  self.blocklisted_responder = lambda do |_request|
    [302, { "Location" => "/users/sign_in?geoblocked=true" }, []]
  end

  self.throttled_responder = lambda do |_request|
    [
      429,
      { "Content-Type" => "text/html; charset=utf-8" },
      ["<h1>429 Too Many Requests</h1><p>Too many requests. Please wait a minute and try again.</p>"]
    ]
  end
end
