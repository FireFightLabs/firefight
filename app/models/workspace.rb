class Workspace < ApplicationRecord
  # Enums - Keep teams for future extensibility but only implement Slack for now
  enum :platform, { slack: "slack", teams: "teams" }, suffix: true

  # Associations
  has_many :workspace_memberships, dependent: :destroy
  has_many :users, through: :workspace_memberships

  # Encryptions - Rails 7+ native encryption
  encrypts :access_token, :refresh_token, deterministic: false

  # Validations
  validates :platform, :platform_id, :name, :installed_at, presence: true
  validates :platform_id, uniqueness: { scope: :platform }

  # Scopes
  scope :by_platform, ->(platform) { where(platform: platform) }
  scope :slack_platform, -> { where(platform: "slack") }
  scope :recent, -> { order(created_at: :desc) }

  # Class Methods
  def self.find_or_create_from_slack!(auth_hash)
    team_info = auth_hash.extra.team_info

    find_or_create_by!(
      platform: :slack,
      platform_id: team_info["id"]
    ) do |workspace|
      workspace.name = team_info["name"]
      workspace.platform_data = team_info
      workspace.access_token = auth_hash.credentials.token
      workspace.refresh_token = auth_hash.credentials.refresh_token if auth_hash.credentials.refresh_token
      workspace.token_expires_at = Time.at(auth_hash.credentials.expires_at) if auth_hash.credentials.expires_at
      workspace.installed_at = Time.current
    end
  end

  # Instance Methods
  def token_expired?
    token_expires_at.present? && token_expires_at < Time.current
  end
end
