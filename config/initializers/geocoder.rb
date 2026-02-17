# config/initializers/geocoder.rb
Geocoder.configure(
  # We set a placeholder or a default here
  ip_lookup: :ipinfo_io,

  # Other static settings
  use_https: true,
  timeout: 16,
  units: :km,
  cache: Rails.cache
)
