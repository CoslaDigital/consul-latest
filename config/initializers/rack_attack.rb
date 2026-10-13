# config/initializers/rack_attack.rb
require "maxmind/db"

class Rack::Attack
  # 1. In-memory cache capped at 32MB with LRU eviction (No Redis needed)
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new(size: 32.megabytes)

  # 2. Load the GeoIP database into RAM once at boot
  GEOIP_PATH = Rails.root.join("db", "geoip", "GeoLite2-Country.mmdb")
  GEOIP_DB = File.exist?(GEOIP_PATH) ? MaxMind::DB.new(GEOIP_PATH.to_s, mode: MaxMind::DB::MODE_MEMORY) : nil

  # 3. Determine the real client IP (allows dev curl testing without opening a hole in prod)
  def self.client_ip(req)
    if Rails.env.development? || Rails.env.test?
      forwarded = req.get_header("HTTP_X_FORWARDED_FOR")
      return forwarded.split(",").first.strip if forwarded.present?
    end

    # In production, use ActionDispatch::RemoteIp (which strips untrusted reverse proxy headers)
    req.get_header("action_dispatch.remote_ip")&.to_s || req.ip
  end

  # Allowed territories: default to UK ("GB"), or read from credentials/Setting
  def self.allowed_countries
    @allowed_countries ||= begin
                             if defined?(Setting) && Setting.respond_to?(:[]) && Setting["geofence_allowed_countries"].present?
                               Setting["geofence_allowed_countries"].to_s.split(",").map(&:strip).map(&:upcase)
                             else
                               Rails.application.credentials.dig(:geofence, :allowed_countries) || ["GB"]
                             end
                           end
  end

  # 4. Safelist internal loops (unless testing with X-Forwarded-For in development)
  safelist("allow-internal-ips") do |req|
    ip = client_ip(req)
    (ip == "127.0.0.1" || ip == "::1") && (Rails.env.production? || req.get_header("HTTP_X_FORWARDED_FOR").blank?)
  end

  # 5. Geofence Rule: Intercept POST /ys_login from outside permitted countries
  blocklist("geofence-ys-login") do |req|
    is_ys_login = (req.path == "/ys_login" || req.path == "/ys_login/") && req.post?

    if is_ys_login && GEOIP_DB
      ip = client_ip(req)
      record = GEOIP_DB.get(ip)
      country_code = record&.dig("country", "iso_code")

      # Block if IP resolved to a country outside our allowed list
      country_code.present? && !allowed_countries.include?(country_code)
    else
      false
    end
  end

  # 6. Throttle: Max 10 login submissions per minute per IP
  throttle("limit-ys-login-attempts", limit: 10, period: 1.minute) do |req|
    if (req.path == "/ys_login" || req.path == "/ys_login/") && req.post?
      client_ip(req)
    end
  end

  # 7. Blanket DoS Throttle: Max 300 requests per 5 minutes per IP (ignoring assets)
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    client_ip(req) unless req.path.start_with?("/assets", "/packs", "/vite")
  end

  # 8. Responder: Redirect geoblocked requests back to sign-in with a query flag
  self.blocklisted_responder = lambda do |_request|
    [
      302,
      { "Location" => "/ys_login/new?geoblocked=true" },
      []
    ]
  end

  # 9. Responder: Throttled response (HTTP 429)
  self.throttled_responder = lambda do |_request|
    [
      429,
      { "Content-Type" => "text/html; charset=utf-8" },
      ["<h1>429 Too Many Requests</h1><p>Too many requests. Please wait a minute and try again.</p>"]
    ]
  end
end
