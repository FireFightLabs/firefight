class Workspace < ApplicationRecord
  include Workspace::IncidentDefaults
  include Workspace::CatalogueDefaults
  include Workspace::Suspension
  include Workspace::Connection
  include Workspace::ChannelArchival

  enum :platform, { slack: Platforms::SLACK, teams: Platforms::TEAMS }, suffix: true

  # Destroyed in declaration order. Children go before the rows they hold
  # foreign keys to, memberships last because nearly every table names one.
  has_many :ability_invocations, class_name: "Ability::Invocation", dependent: :delete_all
  has_many :ability_approvals, class_name: "Ability::Approval", dependent: :destroy
  has_many :ability_grants, class_name: "Ability::Grant", dependent: :destroy
  has_many :ai_model_overrides, dependent: :destroy
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
  has_one :onboarding, class_name: "WorkspaceOnboarding", dependent: :destroy
  has_many :workspace_memberships, dependent: :destroy
  has_many :users, through: :workspace_memberships

  # The one list grant scoping and connection wiring both read, so an id from
  # a form is checked against exactly what the UI offered.
  has_many :environment_entries, -> { in_system_type(CatalogType::SYSTEM_KEY_ENVIRONMENT).order(:name) },
           class_name: "CatalogEntry", inverse_of: :workspace

  encrypts :access_token, :refresh_token, deterministic: false

  validates :platform, :platform_id, :name, :installed_at, presence: true
  validates :platform_id, uniqueness: { scope: :platform }

  scope :by_platform, ->(platform) { where(platform: platform) }
  scope :slack_platform, -> { where(platform: Platforms::SLACK) }
  scope :recent, -> { order(created_at: :desc) }

  # Also the fallback for sources without their own policy. Mirrors the
  # AlertSource methods so callers treat (source || workspace) as one scope.
  def alert_routing_policy
    policies.for_domain(Policy::DOMAIN_ALERT_ROUTING).workspace_wide.first
  end

  # nil when the policy is disabled, matching AlertSource#effective_alert_routing_policy.
  def effective_alert_routing_policy
    [ alert_routing_policy ].compact.detect(&:enabled?)
  end

  # Mirrors AlertSource#routing_fields. With no source to name, the fields stand as given.
  def routing_fields(fields)
    fields
  end

  # IncidentStatus refuses to disable or delete a stage's last enabled status,
  # so this always finds one.
  def default_canceled_status
    incident_statuses.canceled.active.ordered.first!
  end

  # Where a reopened incident lands.
  def default_live_status
    live = incident_statuses.active.live
    live.find_by(is_default: true) || live.ordered.first!
  end

  def find_or_create_alert_routing_policy!
    alert_routing_policy ||
      policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: Policy::DEFAULT_ALERT_ROUTING_NAME)
  end

  # The policy only exists once an admin writes the first rule.
  def approval_policy
    policies.for_domain(Policy::DOMAIN_APPROVALS).workspace_wide.first
  end

  def find_or_create_approval_policy!
    approval_policy ||
      policies.create!(domain: Policy::DOMAIN_APPROVALS, name: Policy::DEFAULT_APPROVALS_NAME)
  end

  def approval_rules
    approval_policy&.ordered_rules || PolicyRule.none
  end

  # Unknown slugs are dropped, matching the dashboard.
  def environment_ids_for(slugs)
    environment_entries.where(slug: Array(slugs).map(&:to_s)).pluck(:id)
  end

  validates :transcript_retention_days,
            numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # A grant says who may ask. This is the admin's separate call on whether the
  # transcript is readable at all.
  def transcript_access_blocked_reason
    return nil if transcript_access_enabled

    "This workspace has not turned on transcript access. An admin can enable it under Settings, Workspace."
  end

  # Nil keeps them forever, which a workspace can choose knowing what it means.
  def transcripts_purge_after
    transcript_retention_days&.days
  end

  # Reference attributes hold the type id inside their config, so there is no
  # association to preload. This avoids a query per attribute.
  def catalog_type_by_id(id)
    @catalog_types_by_id ||= catalog_types.active.index_by(&:id)
    @catalog_types_by_id[id]
  end

  def adapter
    WorkspaceAdapter.for(self)
  end

  # Returns the row an admin customized, otherwise creates one from the
  # defaults so overlay rows have a real incident_form_id to attach to.
  def ensure_incident_form!(slug)
    incident_forms.find_or_create_by!(slug: slug) do |form|
      defaults = IncidentForm.defaults_for(slug)
      raise ArgumentError, "Unknown incident form slug: #{slug}" unless defaults

      form.assign_attributes(defaults)
    end
  end

  # Returns the existing row, otherwise creates one from the defaults so
  # assignments have a real incident_role_id.
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

  # user comes from the prior OIDC sign-in. The bot install's users.info fetch
  # is brittle, so identity is never derived from auth_hash when user is given.
  def self.process_slack_installation(auth_hash, user: nil)
    transaction do
      workspace = find_or_create_from_slack!(auth_hash)
      user ||= User.find_or_create_from_omniauth!(auth_hash)
      membership = WorkspaceMembership.find_or_create_from_omniauth!(user, workspace, auth_hash)

      if workspace.previously_new_record?
        workspace.setup_incident_configuration!
        workspace.setup_catalogue!
      end

      first_install = workspace.previously_new_record? || workspace.incidents_channel_id.blank?
      workspace.create_onboarding!(installer: membership) if first_install && workspace.onboarding.nil?

      {
        workspace: workspace,
        user: user,
        membership: membership,
        first_install: first_install
      }
    end
  end
end
