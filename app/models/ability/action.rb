module Ability
  # The atomic permissioned unit of the Ability Gateway. System actions are
  # global rows (workspace_id nil), one per resource and CRUD action below.
  # Tool actions are workspace-scoped and minted by integrations.
  #
  # The resource and action vocabulary lives here because this is the
  # permission system. API keys, Slack handlers, MCP tools, and the web
  # dashboard all declare what they authorize in these terms.
  class Action < ApplicationRecord
    KIND_SYSTEM = "system"
    KIND_TOOL = "tool"
    KINDS = [ KIND_SYSTEM, KIND_TOOL ].freeze

    RESOURCE_INCIDENTS = "incidents"
    RESOURCE_SEVERITIES = "severities"
    RESOURCE_STATUSES = "statuses"
    RESOURCE_INCIDENT_TYPES = "incident_types"
    RESOURCE_CUSTOM_FIELDS = "custom_fields"
    # Which fields a responder is asked at each lifecycle moment. Separate
    # from custom_fields because defining a field and deciding that Name is
    # required on every declaration are different powers.
    RESOURCE_FORMS = "forms"
    RESOURCE_CATALOG = "catalog"
    RESOURCE_ALERTS = "alerts"
    RESOURCE_POLICIES = "policies"
    RESOURCE_RUNBOOKS = "runbooks"
    RESOURCE_APPROVALS = "approvals"
    RESOURCE_INCIDENT_ROLES = "incident_roles"
    # Its own resource rather than part of incidents, because reading an
    # incident and reading everything anyone said in its channel are different
    # asks. Folding it in would have widened every grant already made.
    RESOURCE_INCIDENT_TRANSCRIPTS = "incident_transcripts"
    RESOURCE_WEBHOOKS = "webhooks"
    RESOURCE_INTEGRATIONS = "integrations"
    RESOURCE_API_KEYS = "api_keys"
    RESOURCE_PERMISSIONS = "permissions"
    RESOURCE_WORKSPACE = "workspace"

    # The levers that control access itself. Admins hold them and nobody can
    # be granted them, so a member or an agent can never mint keys or rewrite
    # who has what.
    ADMIN_ONLY_RESOURCES = [
      RESOURCE_INTEGRATIONS, RESOURCE_API_KEYS, RESOURCE_PERMISSIONS, RESOURCE_WORKSPACE
    ].freeze

    GRANTABLE_RESOURCES = [
      RESOURCE_INCIDENTS, RESOURCE_SEVERITIES, RESOURCE_STATUSES, RESOURCE_INCIDENT_TYPES,
      RESOURCE_CUSTOM_FIELDS, RESOURCE_FORMS, RESOURCE_CATALOG, RESOURCE_ALERTS, RESOURCE_POLICIES,
      RESOURCE_RUNBOOKS, RESOURCE_APPROVALS, RESOURCE_INCIDENT_ROLES, RESOURCE_WEBHOOKS,
      RESOURCE_INCIDENT_TRANSCRIPTS
    ].freeze

    RESOURCES = (GRANTABLE_RESOURCES + ADMIN_ONLY_RESOURCES).freeze

    RESOURCE_LABELS = {
      RESOURCE_INCIDENTS => "Incidents",
      RESOURCE_SEVERITIES => "Severities",
      RESOURCE_STATUSES => "Statuses",
      RESOURCE_INCIDENT_TYPES => "Incident Types",
      RESOURCE_CUSTOM_FIELDS => "Custom Fields",
      RESOURCE_FORMS => "Forms",
      RESOURCE_CATALOG => "Catalogue",
      RESOURCE_ALERTS => "Alerts",
      RESOURCE_POLICIES => "Alert Routing",
      RESOURCE_RUNBOOKS => "Runbooks",
      RESOURCE_APPROVALS => "Approvals",
      RESOURCE_INCIDENT_ROLES => "Incident Roles",
      RESOURCE_INCIDENT_TRANSCRIPTS => "Incident Transcripts",
      RESOURCE_WEBHOOKS => "Webhooks",
      RESOURCE_INTEGRATIONS => "Integrations",
      RESOURCE_API_KEYS => "API Keys",
      RESOURCE_PERMISSIONS => "Permissions",
      RESOURCE_WORKSPACE => "Workspace"
    }.freeze

    ACTION_READ = "read"
    ACTION_CREATE = "create"
    ACTION_UPDATE = "update"
    ACTION_DELETE = "delete"

    ACTIONS = [ ACTION_READ, ACTION_CREATE, ACTION_UPDATE, ACTION_DELETE ].freeze

    RISK_READ = "read"
    RISK_WRITE = "write"
    RISK_DESTRUCTIVE = "destructive"
    RISK_LEVELS = [ RISK_READ, RISK_WRITE, RISK_DESTRUCTIVE ].freeze

    RISK_BY_CRUD_ACTION = {
      ACTION_READ => RISK_READ,
      ACTION_CREATE => RISK_WRITE,
      ACTION_UPDATE => RISK_WRITE,
      ACTION_DELETE => RISK_DESTRUCTIVE
    }.freeze

    KEY_FORMAT = /\A[a-z0-9_]+(\.[a-z0-9_]+)+\z/

    belongs_to :workspace, optional: true
    belongs_to :source, polymorphic: true, optional: true
    has_many :grants, class_name: "Ability::Grant", foreign_key: :action_id, dependent: :destroy,
             inverse_of: :action
    has_many :role_actions, class_name: "Ability::RoleAction", foreign_key: :action_id,
             dependent: :destroy, inverse_of: :action

    validates :kind, inclusion: { in: KINDS }
    validates :risk_level, inclusion: { in: RISK_LEVELS }
    validates :key, presence: true, format: { with: KEY_FORMAT }
    validates :key, uniqueness: { scope: :workspace_id }
    validate :system_actions_are_global

    scope :system_actions, -> { where(kind: KIND_SYSTEM) }

    # The controls that decide access never wait on a rule. Resolving an
    # approval is the approval mechanism, and a rule that could hold the
    # Permissions screen could lock the admins out of removing it.
    APPROVAL_EXEMPT_RESOURCES = [ RESOURCE_APPROVALS, RESOURCE_PERMISSIONS ].freeze

    def self.approval_exempt?(key)
      APPROVAL_EXEMPT_RESOURCES.include?(resource_of(key))
    end
    scope :grantable, -> { where.not(key: admin_only_keys) }
    scope :grantable_for, ->(workspace) { where(workspace_id: [ nil, workspace.id ]).grantable }

    def self.system_key(resource, action)
      "#{resource}.#{action}"
    end

    # Every system action key. Lookup self-heals any of them.
    def self.managed_keys
      @managed_keys ||= RESOURCES.product(ACTIONS).map { |resource, action| system_key(resource, action) }.freeze
    end

    # The keys a grant or a permissions matrix may carry.
    def self.grantable_keys
      @grantable_keys ||= GRANTABLE_RESOURCES.product(ACTIONS).map { |resource, action| system_key(resource, action) }.freeze
    end

    def self.admin_only_keys
      @admin_only_keys ||= ADMIN_ONLY_RESOURCES.product(ACTIONS).map { |resource, action| system_key(resource, action) }.freeze
    end

    def self.resource_of(key)
      key.to_s.split(".").first
    end

    def self.label(resource)
      RESOURCE_LABELS.fetch(resource, resource.to_s.humanize)
    end

    # A key resolves to the global system action or the workspace's own
    # tool action. Keys inside the system space self-heal (same rule as
    # system!, so an unseeded environment can't deny valid actions). Any
    # other unknown key resolves to nil and the gateway denies it.
    def self.lookup(key, workspace)
      found = where(workspace_id: [ nil, workspace&.id ]).find_by(key: key)
      return found if found

      system!(key) if managed_keys.include?(key)
    end

    # Lazily materializes a system action so grant writes never race the
    # seed. Safe under parallel creation via the partial unique index.
    def self.system!(key)
      crud_action = key.split(".").last
      find_or_create_by!(workspace_id: nil, key: key) do |action|
        action.kind = KIND_SYSTEM
        action.risk_level = RISK_BY_CRUD_ACTION.fetch(crud_action, RISK_WRITE)
        action.reversible = action.risk_level != RISK_DESTRUCTIVE
      end
    rescue ActiveRecord::RecordNotUnique
      find_by!(workspace_id: nil, key: key)
    end

    def self.sync_system_actions!
      RESOURCES.each do |resource|
        ACTIONS.each do |action|
          system!(system_key(resource, action))
        end
      end
    end

    def system?
      kind == KIND_SYSTEM
    end

    def admin_only?
      system? && ADMIN_ONLY_RESOURCES.include?(self.class.resource_of(key))
    end

    # Config ≠ permission: a tool action also needs whatever minted it to be
    # wired for the requested scope. What "wired" means belongs to the source,
    # not to the gateway. System actions have no configuration dimension.
    def configured_for?(scope)
      return true if system?

      source.present? && source.configured_for?(scope)
    end

    private

    def system_actions_are_global
      errors.add(:workspace_id, "must be blank for system actions") if system? && workspace_id.present?
      errors.add(:workspace_id, "is required for tool actions") if !system? && workspace_id.blank?
    end
  end
end
