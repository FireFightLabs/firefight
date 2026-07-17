class AlertSource < ApplicationRecord
  PROVIDER_GENERIC = "generic"
  PROVIDER_NORTHFLANK = "northflank"
  PROVIDERS = [ PROVIDER_GENERIC, PROVIDER_NORTHFLANK ].freeze

  DEFAULT_RATE_LIMIT_PER_MINUTE = 60
  DEFAULT_FINGERPRINT_FIELDS = %w[service title].freeze
  DEFAULT_FLAP_WINDOW_MINUTES = 5
  FLAP_WINDOW_MINUTES_RANGE = (0..60).freeze

  encrypts :secret_token

  belongs_to :workspace
  has_many :alerts, dependent: :destroy
  has_one :alert_routing_policy, -> { for_domain(Policy::DOMAIN_ALERT_ROUTING) },
          class_name: "Policy", as: :scoped_to, dependent: :destroy

  before_validation :generate_credentials, on: :create

  validates :name, presence: true, uniqueness: { scope: :workspace_id }
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :endpoint_path, presence: true, uniqueness: true
  validates :secret_token, presence: true

  scope :enabled, -> { where(enabled: true) }

  def adapter
    AlertProviders.for(provider)
  end

  # What fires at ingest: this source's own policy wins; the workspace-wide
  # policy is the shared fallback for sources without one. For the policy
  # being edited (never the inherited fallback), use alert_routing_policy.
  def effective_alert_routing_policy
    [ alert_routing_policy, workspace.alert_routing_policy ].compact.detect(&:enabled?)
  end

  def find_or_create_alert_routing_policy!
    alert_routing_policy ||
      workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: Policy::DEFAULT_ALERT_ROUTING_NAME, scoped_to: self)
  end

  # Ingest diagnostics for the sources UI; update_columns keeps the hot path
  # free of callbacks and updated_at churn.
  def record_received!
    update_columns(last_received_at: Time.current)
  end

  def record_rejection!(reason)
    update_columns(last_rejected_at: Time.current, last_rejection_reason: reason)
  end

  def rate_limit_per_minute
    config.fetch("rate_limit_per_minute", DEFAULT_RATE_LIMIT_PER_MINUTE).to_i
  end

  # Which normalized fields identify "the same alert" when the provider sends
  # no fingerprint of its own.
  def fingerprint_fields
    Array(config["fingerprint_fields"]).presence || DEFAULT_FINGERPRINT_FIELDS
  end

  def flap_window
    config.fetch("flap_window_minutes", DEFAULT_FLAP_WINDOW_MINUTES).to_i.minutes
  end

  # Per-source static map ({"critical" => severity_id}) with the workspace
  # default severity as fallback.
  def resolve_severity(severity_raw)
    mapped_id = config.dig("severity_map", severity_raw.to_s.downcase)
    severity = workspace.incident_severities.active.find_by(id: mapped_id) if mapped_id.present?
    severity || workspace.incident_severities.default_severity
  end

  private

  def generate_credentials
    self.endpoint_path ||= SecureRandom.urlsafe_base64(18)
    self.secret_token ||= SecureRandom.hex(24)
  end
end
