class Workspace < ApplicationRecord
  include Workspace::IncidentDefaults
  include Workspace::CatalogueDefaults
  include Workspace::Suspension
  include Workspace::Connection

  enum :platform, { slack: Platforms::SLACK, teams: Platforms::TEAMS }, suffix: true

  # Destroyed in declaration order, and the order is load-bearing: children
  # go before the rows they hold foreign keys to. Grants before the actions
  # they name, webhook deliveries before the incident events they point at,
  # incidents before the options, runbooks, catalogs and keys they
  # reference, inferences and api keys after the incidents that name them,
  # memberships last because nearly every table names one.
  has_many :ability_invocations, class_name: "Ability::Invocation", dependent: :delete_all
  has_many :ability_approvals, class_name: "Ability::Approval", dependent: :destroy
  has_many :ability_grants, class_name: "Ability::Grant", dependent: :destroy
  has_many :ability_roles, class_name: "Ability::Role", dependent: :destroy
  has_many :webhooks, dependent: :destroy
  has_many :alerts, dependent: :destroy
  has_many :alert_groups, dependent: :destroy
  has_many :incidents, dependent: :destroy
  has_many :alert_sources, dependent: :destroy
  has_many :policies, dependent: :destroy
  has_many :agents, dependent: :destroy
  has_many :integrations, dependent: :destroy
  has_many :ability_actions, class_name: "Ability::Action", dependent: :destroy
  has_many :incident_runbooks, dependent: :destroy
  has_many :runbooks, dependent: :destroy
  has_many :incident_conditions, dependent: :delete_all
  has_many :incident_forms, dependent: :destroy
  has_many :incident_field_definitions, dependent: :destroy
  has_many :catalog_entry_relationships, dependent: :delete_all
  has_many :catalog_entries, dependent: :destroy
  has_many :catalog_types, dependent: :destroy
  has_many :incident_statuses, dependent: :destroy
  has_many :incident_severities, dependent: :destroy
  has_many :incident_roles, dependent: :destroy
  has_many :incident_types, dependent: :destroy
  has_many :incident_transcript_messages, dependent: :destroy
  has_many :inferences, dependent: :delete_all
  has_many :idempotency_keys, dependent: :delete_all
  has_many :api_keys, dependent: :destroy
  has_many :workspace_memberships, dependent: :destroy
  has_many :users, through: :workspace_memberships

  # The environments a grant may be scoped to and a connection's credentials
  # wired for. The single source both questions are answered from, so an id
  # arriving from a form is verified against exactly what the UI offered.
  has_many :environment_entries, -> { active.joins(:catalog_type).where(catalog_types: { system_key: CatalogType::SYSTEM_KEY_ENVIRONMENT }).order(:name) },
           class_name: "CatalogEntry", inverse_of: :workspace

  encrypts :access_token, :refresh_token, deterministic: false

  validates :platform, :platform_id, :name, :installed_at, presence: true
  validates :platform_id, uniqueness: { scope: :platform }

  scope :by_platform, ->(platform) { where(platform: platform) }
  scope :slack_platform, -> { where(platform: Platforms::SLACK) }
  scope :recent, -> { order(created_at: :desc) }

  # The workspace-wide policy, edited directly at workspace scope and the
  # shared fallback for sources without their own. Mirrors the AlertSource
  # methods of the same names so callers can treat (source || workspace) as
  # one routing scope.
  def alert_routing_policy
    policies.for_domain(Policy::DOMAIN_ALERT_ROUTING).workspace_wide.first
  end

  # What fires at ingest for this scope. nil when the policy is disabled,
  # matching AlertSource#effective_alert_routing_policy.
  def effective_alert_routing_policy
    [ alert_routing_policy ].compact.detect(&:enabled?)
  end

  # Workspace-scoped evaluation has no source to name, so the fields stand as
  # given. Mirrors AlertSource#routing_fields.
  def routing_fields(fields)
    fields
  end

  # Every stage keeps at least one enabled status (IncidentStatus refuses to
  # disable or delete the last one), so this is a lookup, not a question.
  def default_canceled_status
    incident_statuses.canceled.active.ordered.first!
  end

  def find_or_create_alert_routing_policy!
    alert_routing_policy ||
      policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: Policy::DEFAULT_ALERT_ROUTING_NAME)
  end

  def adapter
    WorkspaceAdapter.for(self)
  end

  # Lazily materializes a built-in incident form. Returns the existing DB
  # row when an admin has already customized the form. otherwise creates
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
  # row when present. otherwise creates one from `IncidentRole::DEFAULTS`.
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
      installed_at: workspace.new_record? ? Time.current : workspace.installed_at,
      disconnected_at: nil,
      disconnected_reason: nil
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
  #   users.info fetch is brittle and not required, identity already exists.
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
end
