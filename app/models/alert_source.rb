class AlertSource < ApplicationRecord
  include StormControl

  PROVIDER_GENERIC = "generic"
  PROVIDER_NORTHFLANK = "northflank"
  PROVIDER_PAGERDUTY = "pagerduty"
  PROVIDER_OPSGENIE = "opsgenie"
  PROVIDER_SENTRY = "sentry"
  PROVIDER_DATADOG = "datadog"
  PROVIDER_GRAFANA = "grafana"
  PROVIDER_ALERTMANAGER = "alertmanager"
  PROVIDER_NEW_RELIC = "new_relic"
  PROVIDER_HONEYCOMB = "honeycomb"
  PROVIDER_AXIOM = "axiom"
  PROVIDER_BETTER_STACK = "better_stack"
  PROVIDER_HONEYBADGER = "honeybadger"
  PROVIDER_OPENSTATUS = "openstatus"
  PROVIDER_SIGNOZ = "signoz"
  PROVIDER_POSTHOG = "posthog"
  PROVIDER_MIXPANEL = "mixpanel"
  PROVIDER_LOGFIRE = "logfire"
  PROVIDERS = [
    PROVIDER_GENERIC, PROVIDER_NORTHFLANK, PROVIDER_PAGERDUTY, PROVIDER_OPSGENIE, PROVIDER_SENTRY, PROVIDER_DATADOG,
    PROVIDER_GRAFANA, PROVIDER_ALERTMANAGER, PROVIDER_NEW_RELIC, PROVIDER_HONEYCOMB, PROVIDER_AXIOM, PROVIDER_BETTER_STACK,
    PROVIDER_HONEYBADGER, PROVIDER_OPENSTATUS, PROVIDER_SIGNOZ, PROVIDER_POSTHOG, PROVIDER_MIXPANEL,
    PROVIDER_LOGFIRE
  ].freeze

  DEFAULT_RATE_LIMIT_PER_MINUTE = 60
  DEFAULT_FINGERPRINT_FIELDS = %w[service title].freeze
  DEFAULT_FLAP_WINDOW_MINUTES = 5
  FLAP_WINDOW_MINUTES_RANGE = (0..60).freeze
  SECRET_MAX_LENGTH = 512
  SECRET_HINT_LENGTH = 4

  encrypts :secret_token

  belongs_to :workspace
  has_many :alerts, dependent: :destroy
  has_one :alert_routing_policy, -> { for_domain(Policy::DOMAIN_ALERT_ROUTING) },
          class_name: "Policy", as: :scoped_to, dependent: :destroy

  before_validation :generate_credentials, on: :create

  validates :name, presence: true, uniqueness: { scope: :workspace_id }
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :endpoint_path, presence: true, uniqueness: true
  validates :secret_token, presence: true, length: { maximum: SECRET_MAX_LENGTH }

  scope :enabled, -> { where(enabled: true) }

  def self.new_secret = SecureRandom.hex(24)

  # The source's own policy wins, the workspace policy is the fallback. To
  # edit, use alert_routing_policy, never the inherited one.
  def effective_alert_routing_policy
    [ alert_routing_policy, workspace.alert_routing_policy ].compact.detect(&:enabled?)
  end

  # Ingest, the route tester and MCP all go through here so a rule on
  # provider matches the same way everywhere.
  def routing_fields(fields)
    fields.merge("source" => name, "provider" => provider)
  end

  def find_or_create_alert_routing_policy!
    alert_routing_policy ||
      workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: Policy::DEFAULT_ALERT_ROUTING_NAME, scoped_to: self)
  end

  # update_columns keeps the ingest hot path free of callbacks and updated_at churn.
  def record_received!
    update_columns(last_received_at: Time.current)
  end

  def record_rejection!(reason)
    update_columns(last_rejected_at: Time.current, last_rejection_reason: reason)
  end

  # For a provider that signs with a secret of its own making, which the person pastes in place of the generated one.
  def replace_secret(value)
    self.secret_token = value.to_s.strip
    self.config = config.merge("secret_saved_at" => Time.current.iso8601)
  end

  # A new token in place of the old, which stops working at once. For a source whose token is part of its address, this
  # is a new address.
  def regenerate_secret!
    update!(secret_token: self.class.new_secret)
  end

  # "Secret ending in 4f2a. Enter a new one to replace it.", or nil until a secret has been pasted in.
  def secret_summary
    return if config["secret_saved_at"].blank?

    "Secret ending in #{secret_token.last(SECRET_HINT_LENGTH)}. Enter a new one to replace it."
  end

  def rate_limit_per_minute
    config.fetch("rate_limit_per_minute", DEFAULT_RATE_LIMIT_PER_MINUTE).to_i
  end

  # Used when the provider sends no fingerprint of its own.
  def fingerprint_fields
    Array(config["fingerprint_fields"]).presence || DEFAULT_FINGERPRINT_FIELDS
  end

  def flap_window
    config.fetch("flap_window_minutes", DEFAULT_FLAP_WINDOW_MINUTES).to_i.minutes
  end

  def resolve_severity(severity_raw)
    mapped_id = config.dig("severity_map", severity_raw.to_s.downcase)
    severity = workspace.incident_severities.active.find_by(id: mapped_id) if mapped_id.present?
    severity || workspace.incident_severities.default_severity
  end

  private

  def generate_credentials
    self.endpoint_path ||= SecureRandom.urlsafe_base64(18)
    self.secret_token ||= self.class.new_secret
  end
end
