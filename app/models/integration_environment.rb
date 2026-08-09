# Per-environment wiring for an integration: encrypted credentials + config
# + the enabled flag. "Configured for prod" (this row) and "permitted in
# prod" (a grant) are separate facts; the gateway requires both.
class IntegrationEnvironment < ApplicationRecord
  HEALTH_UNKNOWN = "unknown"
  HEALTH_HEALTHY = "healthy"
  HEALTH_FAILING = "failing"
  HEALTH_STATUSES = [ HEALTH_UNKNOWN, HEALTH_HEALTHY, HEALTH_FAILING ].freeze
  OAUTH_KEY = "oauth".freeze

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

  # OAuth credential sets are produced and read by Integrations::OauthClient;
  # this row owns storing them and nothing else looks inside.
  def oauth
    credentials_hash[OAUTH_KEY]
  end

  def store_oauth!(oauth_credentials, installation_id: nil)
    self.credentials = credentials_hash.merge(OAUTH_KEY => oauth_credentials).to_json
    # GitHub App installs return an installation id alongside the code. It is
    # not a secret, so it lives in base_config; server-to-server tokens (the
    # bot identity for autonomous agent writes) are minted from it later.
    self.base_config = base_config.merge("installation_id" => installation_id.to_s) if installation_id.present?
    save!
    oauth_credentials
  end

  # The native install-first path (GitHub App): no OAuth credentials come
  # back, only the installation id that server-to-server tokens are minted
  # from at call time.
  def store_installation!(installation_id)
    update!(base_config: base_config.merge("installation_id" => installation_id.to_s))
  end

  def rotate_oauth!(oauth_credentials)
    update!(credentials: credentials_hash.merge(OAUTH_KEY => oauth_credentials).to_json)
    oauth_credentials
  end

  def record_health!(healthy, error: nil)
    update!(health_status: healthy ? HEALTH_HEALTHY : HEALTH_FAILING,
            health_error: healthy ? nil : error, health_checked_at: Time.current)
  end
end
