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
  has_many :incident_field_definitions, dependent: :destroy
  has_many :incident_forms, dependent: :destroy
  has_many :webhooks, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :catalog_types
  has_many :catalog_entries
  has_many :incident_transcript_messages, dependent: :destroy
  has_many :policies, dependent: :destroy
  has_many :alert_sources, dependent: :destroy
  has_many :alerts, dependent: :destroy

  encrypts :access_token, :refresh_token, deterministic: false

  validates :platform, :platform_id, :name, :installed_at, presence: true
  validates :platform_id, uniqueness: { scope: :platform }

  scope :by_platform, ->(platform) { where(platform: platform) }
  scope :slack_platform, -> { where(platform: Platforms::SLACK) }
  scope :recent, -> { order(created_at: :desc) }

  def alert_routing_fallback_policy
    policies.for_domain(Policy::DOMAIN_ALERT_ROUTING).workspace_wide.first
  end

  def find_or_create_alert_routing_fallback_policy!
    alert_routing_fallback_policy ||
      policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: Policy::DEFAULT_ALERT_ROUTING_NAME)
  end

  def adapter
    WorkspaceAdapter.for(self)
  end

  # Lazily materializes a built-in incident form. Returns the existing DB
  # row when an admin has already customized the form; otherwise creates
  # one from `IncidentForm::DEFAULTS`. Callers that need to attach overlay
  # rows (custom fields, system field overrides) use this to get a real
  # `incident_form_id`.
  def ensure_incident_form!(slug)
    incident_forms.find_or_create_by!(slug: slug) do |form|
      defaults = IncidentForm.defaults_for(slug)
      raise ArgumentError, "Unknown incident form slug: #{slug}" unless defaults

      form.assign_attributes(defaults)
    end
  end

  # Lazily materializes a built-in incident role. Returns the existing DB
  # row when present; otherwise creates one from `IncidentRole::DEFAULTS`.
  # Callers that need to create assignments use this to get a real
  # `incident_role_id`.
  def ensure_incident_role!(slug)
    incident_roles.find_or_create_by!(slug: slug) do |role|
      defaults = IncidentRole.defaults_for(slug)
      raise ArgumentError, "Unknown incident role slug: #{slug}" unless defaults

      role.assign_attributes(defaults)
    end
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
  # @param user [User, nil] Pre-identified user from the prior OIDC sign-in.
  #   When provided, skips the auth_hash email lookup. The bot install's
  #   users.info fetch is brittle and not required — identity already exists.
  # @return [Hash] Result with :workspace, :user, :membership, :first_install
  def self.process_slack_installation(auth_hash, user: nil)
    transaction do
      workspace = find_or_create_from_slack!(auth_hash)
      user ||= User.find_or_create_from_omniauth!(auth_hash)
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
