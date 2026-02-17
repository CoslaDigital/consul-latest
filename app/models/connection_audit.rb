# frozen_string_literal: true

class ConnectionAudit < ApplicationRecord
  belongs_to :auditable, polymorphic: true

  # Geocoder setup
  geocoded_by :ip_address
  after_validation :geocode, if: ->(obj) { obj.ip_address.present? }

  # Handy scope for your reporting
  scope :suspicious, -> { where(suspicious: true) }
end
