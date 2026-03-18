# frozen_string_literal: true
module Loggable
  extend ActiveSupport::Concern

  included do
    has_many :connection_audits, as: :auditable, dependent: :destroy
  end

  def create_audit(request)
    connection_audits.create(
      ip_address: request.remote_ip,
      raw_metadata: { user_agent: request.user_agent }
    )
  end
end
