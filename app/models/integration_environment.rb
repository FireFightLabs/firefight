# Per-environment wiring for an integration: encrypted credentials + config
# + the enabled flag. "Configured for prod" (this row) and "permitted in
# prod" (a grant) are separate facts; the gateway requires both.
class IntegrationEnvironment < ApplicationRecord
  HEALTH_UNKNOWN = "unknown"
  HEALTH_HEALTHY = "healthy"
  HEALTH_FAILING = "failing"
  HEALTH_STATUSES = [ HEALTH_UNKNOWN, HEALTH_HEALTHY, HEALTH_FAILING ].freeze

  belongs_to :integration
  belongs_to :environment, class_name: "CatalogEntry", foreign_key: :catalog_entry_id,
             optional: true, inverse_of: false

  encrypts :credentials

  validates :health_status, inclusion: { in: HEALTH_STATUSES }
  validates :catalog_entry_id, uniqueness: { scope: :integration_id }

  scope :enabled, -> { where(enabled: true) }

  def credentials_hash
    JSON.parse(credentials.presence || "{}")
  rescue JSON::ParserError
    {}
  end

  # Headers for outbound calls: either an explicit headers map or a bare
  # authorization value.
  def request_headers
    creds = credentials_hash
    return creds["headers"] if creds["headers"].is_a?(Hash)
    return { "Authorization" => creds["authorization"] } if creds["authorization"].present?

    {}
  end

  def record_health!(healthy)
    update!(health_status: healthy ? HEALTH_HEALTHY : HEALTH_FAILING, health_checked_at: Time.current)
  end
end
