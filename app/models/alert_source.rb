class AlertSource < ApplicationRecord
  PROVIDER_GENERIC = "generic"
  PROVIDER_NORTHFLANK = "northflank"
  PROVIDERS = [ PROVIDER_GENERIC, PROVIDER_NORTHFLANK ].freeze

  DEFAULT_RATE_LIMIT_PER_MINUTE = 60

  encrypts :secret_token

  belongs_to :workspace
  has_many :alerts, dependent: :destroy

  before_validation :generate_credentials, on: :create

  validates :name, presence: true, uniqueness: { scope: :workspace_id }
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :endpoint_path, presence: true, uniqueness: true
  validates :secret_token, presence: true

  scope :enabled, -> { where(enabled: true) }

  def adapter
    AlertProviders.for(provider)
  end

  def rate_limit_per_minute
    config.fetch("rate_limit_per_minute", DEFAULT_RATE_LIMIT_PER_MINUTE).to_i
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
