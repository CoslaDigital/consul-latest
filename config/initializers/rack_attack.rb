require "maxmind/db"

class Rack::Attack
  Rack::Attack.enabled = false
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new(size: 32.megabytes)

  GEOIP_PATH = Rails.root.join("db", "geoip", "GeoLite2-Country.mmdb")
  GEOIP_DB = File.exist?(GEOIP_PATH) ? MaxMind::DB.new(GEOIP_PATH.to_s, mode: MaxMind::DB::MODE_MEMORY) : nil

  # Per-IP login ceiling. Kept as a method so specs can stub it per example without mutating ENV.
  def self.login_ip_limit
    ENV.fetch("RACK_ATTACK_IP_LIMIT", 400).to_i
  end

  def self.login_path?(req)
    (req.path == "/ys_login" || req.path == "/ys_login/") && req.post?
  end

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
    if login_path?(req) && Setting.geofence_card_login_enabled? && GEOIP_DB
      ip = client_ip(req)
      record = GEOIP_DB.get(ip)
      country_code = record&.dig("country", "iso_code")

      country_code.present? && !Setting.geofence_allowed_countries.include?(country_code)
    else
      false
    end
  end

  # 1. Strict limit: Max 10 attempts per minute per email (stops account brute-forcing).
  #    Identity-keyed, so it survives NAT — the whole school shares an IP but not an email.
  throttle("login-per-email", limit: 10, period: 1.minute) do |req|
    if login_path?(req)
      email = req.params["email"].to_s.downcase.strip
      email if email.present?
    end
  end

  # 2. Generous limit: per-IP login ceiling, sized for shared networks.
  #    Keep this the LOOSEST per-IP login rule; it's DoS protection, not brute-force protection.
  throttle("login-per-ip", limit: proc { Rack::Attack.login_ip_limit }, period: 1.minute) do |req|
    client_ip(req) if login_path?(req)
  end

  # Blanket DoS Throttle
  throttle("req/ip", limit: 15000, period: 5.minutes) do |req|
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
