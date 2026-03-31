class Workspace < ApplicationRecord
  include Workspace::IncidentDefaults
  include Workspace::CatalogueDefaults

  enum :platform, { slack: Platforms::SLACK, teams: Platforms::TEAMS }, suffix: true

  has_many :workspace_memberships, dependent: :destroy
  has_many :users, through: :workspace_memberships

  has_many :incidents, dependent: :destroy
  has_many :incident_statuses, dependent: :destroy
  has_many :incident_severities, dependent: :destroy
  has_many :incident_roles, dependent: :destroy
  has_many :incident_types, dependent: :destroy
  has_many :webhooks, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :catalog_types
  has_many :catalog_entries

  encrypts :access_token, :refresh_token, deterministic: false

  validates :platform, :platform_id, :name, :installed_at, presence: true
  validates :platform_id, uniqueness: { scope: :platform }

  scope :by_platform, ->(platform) { where(platform: platform) }
  scope :slack_platform, -> { where(platform: Platforms::SLACK) }
  scope :recent, -> { order(created_at: :desc) }

  def adapter
    WorkspaceAdapter.for(self)
  end

  def self.find_or_create_from_slack!(auth_hash)
    team_info = auth_hash.extra.team_info

    workspace = find_or_initialize_by(
      platform: :slack,
      platform_id: team_info["id"]
    )

    workspace.assign_attributes(
      name: team_info["name"],
      platform_data: team_info,
      access_token: auth_hash.credentials.token,
      refresh_token: auth_hash.credentials.refresh_token,
      token_expires_at: auth_hash.credentials.expires_at ? Time.at(auth_hash.credentials.expires_at) : nil,
      installed_at: workspace.new_record? ? Time.current : workspace.installed_at
    )

    workspace.save!
    workspace
  end

  # Process Slack OAuth installation
  # Coordinates creation of workspace, user, and membership in a transaction
  #
  # @param auth_hash [OmniAuth::AuthHash] OAuth response from Slack
  # @return [Hash] Result with :workspace, :user, :membership, :first_install
  def self.process_slack_installation(auth_hash)
    transaction do
      workspace = find_or_create_from_slack!(auth_hash)
      user = User.find_or_create_from_omniauth!(auth_hash)
      membership = WorkspaceMembership.find_or_create_from_omniauth!(user, workspace, auth_hash)

      if workspace.previously_new_record?
        workspace.setup_incident_configuration!
        workspace.setup_catalogue!
      end

      {
        workspace: workspace,
        user: user,
        membership: membership,
        first_install: workspace.previously_new_record? || workspace.incidents_channel_id.blank?
      }
    end
  end

  def token_expired?
    token_expires_at.present? && token_expires_at < Time.current
  end
end
