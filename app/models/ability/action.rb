module Ability
  # System actions are global rows with a nil workspace_id, one per resource
  # and CRUD action. Tool actions are workspace-scoped and minted by integrations.
  class Action < ApplicationRecord
    KIND_SYSTEM = "system"
    KIND_TOOL = "tool"
    KINDS = [ KIND_SYSTEM, KIND_TOOL ].freeze

    RESOURCE_INCIDENTS = "incidents"
    RESOURCE_SEVERITIES = "severities"
    RESOURCE_STATUSES = "statuses"
    RESOURCE_INCIDENT_TYPES = "incident_types"
    RESOURCE_CUSTOM_FIELDS = "custom_fields"
    # Separate from custom_fields, defining a field and deciding what every
    # declaration must answer are different powers.
    RESOURCE_FORMS = "forms"
    RESOURCE_CATALOG = "catalog"
    RESOURCE_ALERTS = "alerts"
    RESOURCE_POLICIES = "policies"
    RESOURCE_RUNBOOKS = "runbooks"
    RESOURCE_APPROVALS = "approvals"
    RESOURCE_INCIDENT_ROLES = "incident_roles"
    # Its own resource, folding it into incidents would have widened every
    # grant already made.
    RESOURCE_INCIDENT_TRANSCRIPTS = "incident_transcripts"
    RESOURCE_WEBHOOKS = "webhooks"
    RESOURCE_INTEGRATIONS = "integrations"
    RESOURCE_API_KEYS = "api_keys"
    RESOURCE_PERMISSIONS = "permissions"
    RESOURCE_WORKSPACE = "workspace"
    # Its own resource. An investigation spends tokens and posts in the channel,
    # which updating an incident does not.
    RESOURCE_INVESTIGATIONS = "investigations"
    # A person's own chats. Asking in one is investigations.create.
    RESOURCE_CHATS = "chats"
    # What Halon remembers. Adding a fact is create, confirming, correcting, rejecting or disputing one is update.
    RESOURCE_MEMORY = "memory"
    # Reading the resource map. Only read, since curating it is catalog: update and syncing it integrations: update.
    RESOURCE_MAP = "map"
    # The checks Halon runs on a schedule, the problems it raised on its own and the security events that start it.
    RESOURCE_MONITORING = "monitoring"
    # The workspace's own model keys Halon runs on. Admins only, and only from the dashboard.
    RESOURCE_AI_ACCOUNTS = "ai_accounts"
    # The workspace's handbook, which Halon reads first. Members read it, and writing it needs a grant.
    RESOURCE_HANDBOOK = "handbook"
    # Halon's browser in the sandbox. Looking at a page is open like a web lookup. Sending what a page would send, such as
    # a form, is a change, so it needs a grant, the person confirms each one and approval rules hold it.
    RESOURCE_BROWSER = "browser"
    # Posting a message as Firefight in any channel it can post in, such as release notes in #general. It reaches people
    # beyond an incident, so it needs a grant and approval rules hold it. Only posting is offered.
    RESOURCE_CHANNEL_POSTS = "channel_posts"
    # The workspace's own skills, which Halon loads like Firefight's. Members read them, and writing one needs a grant.
    RESOURCE_SKILLS = "skills"
    # A workspace's workflows. Members read them, build drafts from scratch, Firefight's library or a file, test them and
    # run published ones, and publishing one or changing a live one needs update.
    RESOURCE_WORKFLOWS = "workflows"

    # Nobody can be granted these, so a member or an agent can never mint keys
    # or rewrite who has what.
    ADMIN_ONLY_RESOURCES = [
      RESOURCE_INTEGRATIONS, RESOURCE_API_KEYS, RESOURCE_PERMISSIONS, RESOURCE_WORKSPACE, RESOURCE_AI_ACCOUNTS
    ].freeze

    GRANTABLE_RESOURCES = [
      RESOURCE_INCIDENTS, RESOURCE_SEVERITIES, RESOURCE_STATUSES, RESOURCE_INCIDENT_TYPES,
      RESOURCE_CUSTOM_FIELDS, RESOURCE_FORMS, RESOURCE_CATALOG, RESOURCE_ALERTS, RESOURCE_POLICIES,
      RESOURCE_RUNBOOKS, RESOURCE_APPROVALS, RESOURCE_INCIDENT_ROLES, RESOURCE_WEBHOOKS,
      RESOURCE_INCIDENT_TRANSCRIPTS, RESOURCE_INVESTIGATIONS, RESOURCE_CHATS, RESOURCE_MEMORY, RESOURCE_MAP,
      RESOURCE_MONITORING, RESOURCE_HANDBOOK, RESOURCE_BROWSER, RESOURCE_CHANNEL_POSTS, RESOURCE_SKILLS,
      RESOURCE_WORKFLOWS
    ].freeze

    RESOURCES = (GRANTABLE_RESOURCES + ADMIN_ONLY_RESOURCES).freeze

    # Reading the public web through Firefight's own search key reaches nothing of the workspace's, so every person and
    # agent may, with no grant. It leaves Firefight, so the ledger still holds every call. Never on a permission screen.
    RESOURCE_WEB = "web"
    # Starting a database or cache inside the sandbox a coding agent already writes a change in, or running a command in
    # Halon's terminal there, reaches nothing of the workspace's either, so it is open the same way and ledgered the same way.
    RESOURCE_SANDBOX = "sandbox"

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
      RESOURCE_INVESTIGATIONS => "Investigations",
      RESOURCE_CHATS => "Chats",
      RESOURCE_MEMORY => "Memory",
      RESOURCE_MAP => "Resource Map",
      RESOURCE_MONITORING => "Monitoring",
      RESOURCE_HANDBOOK => "Handbook",
      RESOURCE_BROWSER => "Halon's Browser",
      RESOURCE_CHANNEL_POSTS => "Channel Posts",
      RESOURCE_SKILLS => "Skills",
      RESOURCE_WORKFLOWS => "Workflows",
      RESOURCE_WEBHOOKS => "Webhooks",
      RESOURCE_INTEGRATIONS => "Integrations",
      RESOURCE_API_KEYS => "API Keys",
      RESOURCE_PERMISSIONS => "Permissions",
      RESOURCE_WORKSPACE => "Workspace",
      RESOURCE_AI_ACCOUNTS => "AI Accounts"
    }.freeze

    ACTION_READ = "read"
    ACTION_CREATE = "create"
    ACTION_UPDATE = "update"
    ACTION_DELETE = "delete"

    ACTIONS = [ ACTION_READ, ACTION_CREATE, ACTION_UPDATE, ACTION_DELETE ].freeze
    # A resource that only offers some of the actions. Everything else offers all four.
    # The browser's read is open (BROWSER_READ), so only sending is offered.
    RESOURCE_ACTIONS = {
      RESOURCE_MAP => [ ACTION_READ ].freeze, RESOURCE_BROWSER => [ ACTION_UPDATE ].freeze, RESOURCE_CHANNEL_POSTS => [ ACTION_CREATE ].freeze
    }.freeze

    MAP_READ = "#{RESOURCE_MAP}.#{ACTION_READ}".freeze
    HANDBOOK_READ = "#{RESOURCE_HANDBOOK}.#{ACTION_READ}".freeze
    # Asking Halon and starting, steering or stopping an investigation.
    INVESTIGATIONS_CREATE = "#{RESOURCE_INVESTIGATIONS}.#{ACTION_CREATE}".freeze
    # Halon's browser sending what a page would send, such as a form or a button that saves something.
    BROWSER_SUBMIT = "#{RESOURCE_BROWSER}.#{ACTION_UPDATE}".freeze
    # Posting a message as Firefight in a channel someone names.
    CHANNEL_POST = "#{RESOURCE_CHANNEL_POSTS}.#{ACTION_CREATE}".freeze
    # Writes that cannot be taken back once people have read them, like a connected tool's change. A chat asks the person
    # before each one (Conversation::Turn#confirms?) unless they allowed it for the rest of the chat.
    IRREVERSIBLE_KEYS = [ CHANNEL_POST ].freeze
    # Reads whose environment scope narrows what comes back rather than whether the call runs. A call that names no
    # environment is admitted when the principal holds the action in any environment, and the reader keeps to
    # AbilityGateway.reach (ResourceMap::Resource.visible_to for the map).
    FILTERED_KEYS = [ MAP_READ ].freeze

    # What the Permissions screen says about an action beyond its key. Only actions whose key does not say enough have one.
    DESCRIPTIONS = {
      MAP_READ => {
        title: "Read the resource map",
        description: "See what runs where on the resource map, how its resources depend on each other, and each one's fact sheet. " \
                     "Members hold it in every environment without a grant. Granting it to a member, alone or in a set, " \
                     "limits them to the environments ticked here, and an expired grant leaves them none. No access takes it away at once."
      }.freeze,
      BROWSER_SUBMIT => {
        title: "Let Halon send forms in its browser",
        description: "Let Halon submit a form, or press a button that sends data, on a website it checks in its browser, such as " \
                     "placing a test order. Halon stops before anything is sent and the person confirms each one, and approval " \
                     "rules can hold it. Looking at a page needs no grant."
      }.freeze,
      CHANNEL_POST => {
        title: "Post to a channel",
        description: "Post a message as Firefight in any channel it can post in, such as asking Halon to share release notes in " \
                     "#general or a runbook step that announces a release. The post names who asked for it. Members need a grant, " \
                     "approval rules can hold it, and every post is in the activity log."
      }.freeze,
      INVESTIGATIONS_CREATE => {
        title: "Ask Halon and start investigations",
        description: "Ask Halon in a chat, in Slack or over MCP, start an investigation, add to a running one and apply its fix. " \
                     "Members hold it without a grant. Granting it to a member, alone or in a set, means the grant decides, " \
                     "so an expired grant leaves them none. No access takes it away at once."
      }.freeze
    }.freeze

    WEB_READ = "#{RESOURCE_WEB}.#{ACTION_READ}".freeze
    SANDBOX_SERVICE = "#{RESOURCE_SANDBOX}.#{ACTION_CREATE}".freeze
    # A command Halon runs in its terminal, or a check of an address from there. The box holds no key and reaches the
    # workspace's systems only through their own tools, each call authorized as that tool, so the command itself is open.
    SANDBOX_COMMAND = "#{RESOURCE_SANDBOX}.#{ACTION_READ}".freeze
    # Looking at a page in Halon's browser and following its links, menus and searches. The browser sends nothing but
    # GET requests on it, so it reaches nothing of the workspace's and is open the same way, ledgered like the rest.
    BROWSER_READ = "#{RESOURCE_BROWSER}.#{ACTION_READ}".freeze
    OPEN_KEYS = [ WEB_READ, SANDBOX_SERVICE, SANDBOX_COMMAND, BROWSER_READ ].freeze

    RISK_READ = "read"
    RISK_WRITE = "write"
    RISK_DESTRUCTIVE = "destructive"
    RISK_LEVELS = [ RISK_READ, RISK_WRITE, RISK_DESTRUCTIVE ].freeze
    # The risks an approval rule can hold, since a read never waits.
    HELD_RISK_LEVELS = (RISK_LEVELS - [ RISK_READ ]).freeze

    RISK_BY_CRUD_ACTION = {
      ACTION_READ => RISK_READ,
      ACTION_CREATE => RISK_WRITE,
      ACTION_UPDATE => RISK_WRITE,
      ACTION_DELETE => RISK_DESTRUCTIVE
    }.freeze

    # What a change does beyond its risk, which decides the safeguards a call through it gets in a chat. A data write
    # changes rows with a statement, so its rows are counted, copied and checked. A mitigation changes what customers
    # get, such as a block or a flag, so it is undone after a while unless someone keeps it. A stop ends or removes
    # something, so whoever started it is asked first. Declared per tool (Integrations::Effects), never by provider.
    EFFECT_DATA_WRITE = "data_write"
    EFFECT_MITIGATION = "mitigation"
    EFFECT_STOPS = "stops"
    EFFECTS = [ EFFECT_DATA_WRITE, EFFECT_MITIGATION, EFFECT_STOPS ].freeze

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

    # A rule that could hold the Permissions screen could lock admins out of removing it.
    APPROVAL_EXEMPT_RESOURCES = [ RESOURCE_APPROVALS, RESOURCE_PERMISSIONS ].freeze

    # An open action is never held, since a broad rule would stall every lookup. A workspace switches it off instead.
    def self.approval_exempt?(key)
      APPROVAL_EXEMPT_RESOURCES.include?(resource_of(key)) || open?(key)
    end
    # Nobody needs a grant for an open action, so none is offered.
    scope :grantable, -> { where.not(key: admin_only_keys + OPEN_KEYS) }
    scope :grantable_for, ->(workspace) { where(workspace_id: [ nil, workspace.id ]).grantable.where.not(key: hidden_keys(workspace)) }

    # Resources whose work is not switched on for the workspace, which nothing offers until it is.
    def self.hidden_resources(workspace)
      FeatureFlags.enabled?(workspace, FeatureFlags::WORKFLOWS) ? [] : [ RESOURCE_WORKFLOWS ]
    end

    def self.hidden_keys(workspace) = keys_for(hidden_resources(workspace))

    def self.system_key(resource, action)
      "#{resource}.#{action}"
    end

    def self.actions_for(resource) = RESOURCE_ACTIONS.fetch(resource, ACTIONS)

    def self.keys_for(resources) = resources.flat_map { |resource| actions_for(resource).map { |action| system_key(resource, action) } }.freeze

    def self.managed_keys
      @managed_keys ||= keys_for(RESOURCES)
    end

    def self.grantable_keys
      @grantable_keys ||= keys_for(GRANTABLE_RESOURCES)
    end

    def self.admin_only_keys
      @admin_only_keys ||= keys_for(ADMIN_ONLY_RESOURCES)
    end

    def self.filtered?(key) = FILTERED_KEYS.include?(key.to_s)

    def self.described(key) = DESCRIPTIONS[key.to_s]

    def self.resource_of(key)
      key.to_s.split(".").first
    end

    def self.label(resource)
      RESOURCE_LABELS.fetch(resource, resource.to_s.humanize)
    end

    # System keys self-heal so an unseeded environment cannot deny valid
    # actions. Any other unknown key resolves to nil and the gateway denies it.
    def self.lookup(key, workspace)
      found = where(workspace_id: [ nil, workspace&.id ]).find_by(key: key)
      return found if found

      system!(key) if managed_keys.include?(key) || open?(key)
    end

    def self.open?(key) = OPEN_KEYS.include?(key.to_s)

    # Materialized on demand so grant writes never race the seed. The partial
    # unique index makes parallel creation safe.
    def self.system!(key)
      crud_action = key.split(".").last
      find_or_create_by!(workspace_id: nil, key: key) do |action|
        action.kind = KIND_SYSTEM
        action.risk_level = RISK_BY_CRUD_ACTION.fetch(crud_action, RISK_WRITE)
        action.reversible = action.risk_level != RISK_DESTRUCTIVE && IRREVERSIBLE_KEYS.exclude?(key)
      end
    rescue ActiveRecord::RecordNotUnique
      find_by!(workspace_id: nil, key: key)
    end

    def self.sync_system_actions!
      managed_keys.each { |key| system!(key) }
    end

    def system?
      kind == KIND_SYSTEM
    end

    def tool? = kind == KIND_TOOL

    def read? = risk_level == RISK_READ

    # A call to a tool that both reads and changes, which its source shows only reads, such as a GET through an API
    # request tool. The gateway treats it as a read of its connection rather than as the change the tool could make.
    def read_through_guard?(params)
      tool? && !read? && params.present? && source.respond_to?(:reads_call?) && source.reads_call?(params)
    end

    # The risk this one call carries, which is a read for a call shown to read.
    def risk_of(params) = read_through_guard?(params) ? RISK_READ : risk_level

    # Whether no approval rule can ever hold it, since reads never wait and some resources are exempt.
    def never_held? = read? || self.class.approval_exempt?(key)
    # Firefight's own actions have none. A tool's are read from its declaration each time, so a change to the registry or
    # a pack applies without saving anything.
    def effects = tool? && source.respond_to?(:effects) ? source.effects : []

    def effect?(effect) = effects.include?(effect)

    def admin_only?
      system? && ADMIN_ONLY_RESOURCES.include?(self.class.resource_of(key))
    end

    # A tool action also needs whatever minted it wired for the scope. What
    # "wired" means belongs to the source, not the gateway.
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
