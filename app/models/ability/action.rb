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
    # A workflow's HTTP request step calling an address, reading with GET or HEAD and changing with any other method.
    RESOURCE_HTTP_REQUESTS = "http_requests"
    # Lessons from incidents and Halon's own pull requests: deciding on one (approving, editing or turning it down) and
    # letting a pull request through although a strict lesson's finding stands.
    RESOURCE_LESSONS = "lessons"

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
      RESOURCE_WORKFLOWS, RESOURCE_HTTP_REQUESTS, RESOURCE_LESSONS
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
      RESOURCE_HTTP_REQUESTS => "HTTP Requests",
      RESOURCE_SKILLS => "Skills",
      RESOURCE_WORKFLOWS => "Workflows",
      RESOURCE_LESSONS => "Lessons",
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
    # Not one of the four, so neither shows in a create, read, update and delete matrix, only where actions are listed.
    ACTION_DECIDE = "decide"
    ACTION_OVERRIDE = "override"
    # A resource that only offers some of the actions. Everything else offers all four.
    # The browser's read is open (BROWSER_READ), so only sending is offered.
    RESOURCE_ACTIONS = {
      RESOURCE_MAP => [ ACTION_READ ].freeze, RESOURCE_BROWSER => [ ACTION_UPDATE ].freeze, RESOURCE_CHANNEL_POSTS => [ ACTION_CREATE ].freeze,
      RESOURCE_HTTP_REQUESTS => [ ACTION_READ, ACTION_CREATE ].freeze, RESOURCE_LESSONS => [ ACTION_DECIDE, ACTION_OVERRIDE ].freeze
    }.freeze

    MAP_READ = "#{RESOURCE_MAP}.#{ACTION_READ}".freeze
    HANDBOOK_READ = "#{RESOURCE_HANDBOOK}.#{ACTION_READ}".freeze
    # Asking Halon and starting, steering or stopping an investigation.
    INVESTIGATIONS_CREATE = "#{RESOURCE_INVESTIGATIONS}.#{ACTION_CREATE}".freeze
    # Halon's browser sending what a page would send, such as a form or a button that saves something.
    BROWSER_SUBMIT = "#{RESOURCE_BROWSER}.#{ACTION_UPDATE}".freeze
    # Posting a message as Firefight in a channel someone names.
    CHANNEL_POST = "#{RESOURCE_CHANNEL_POSTS}.#{ACTION_CREATE}".freeze
    # Reading a workflow, and building its draft, which is what Halon's proposals to one are.
    WORKFLOWS_READ = "#{RESOURCE_WORKFLOWS}.#{ACTION_READ}".freeze
    WORKFLOWS_CREATE = "#{RESOURCE_WORKFLOWS}.#{ACTION_CREATE}".freeze
    # What a workflow's Approval step asks approvers to decide. It names no tool, since the step changes nothing itself.
    WORKFLOW_APPROVAL = "#{RESOURCE_WORKFLOWS}.approval".freeze
    # A workflow's HTTP request reading an address, and sending one that changes something.
    HTTP_READ = "#{RESOURCE_HTTP_REQUESTS}.#{ACTION_READ}".freeze
    HTTP_SEND = "#{RESOURCE_HTTP_REQUESTS}.#{ACTION_CREATE}".freeze
    # Approving, editing or turning down a lesson. Admins hold it, and a member holds it without a grant for the lessons
    # of an incident they lead and of a pull request they asked Halon for (WorkspaceMembership::OWNED_KEYS).
    LESSON_DECIDE = "#{RESOURCE_LESSONS}.#{ACTION_DECIDE}".freeze
    # Letting a pull request through although a strict lesson's finding stands, which clears its failing check. Admins hold
    # it, and a member holds it without a grant on a pull request whose services they own (WorkspaceMembership::OWNED_KEYS).
    LESSON_OVERRIDE = "#{RESOURCE_LESSONS}.#{ACTION_OVERRIDE}".freeze
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
      HTTP_READ => {
        title: "Read an address over HTTP",
        description: "Let a workflow's HTTP request step read an address with GET or HEAD, through the guard that keeps it off private " \
                     "networks, with a connection's credentials when the step names one and the address is that connection's own."
      }.freeze,
      HTTP_SEND => {
        title: "Send HTTP requests that change something",
        description: "Let a workflow's HTTP request step send POST, PUT, PATCH or DELETE to an address, through the same guard. " \
                     "Approval rules can hold it, and every request is in the activity log."
      }.freeze,
      LESSON_DECIDE => {
        title: "Decide on lessons",
        description: "Approve, edit or turn down a lesson an incident or one of Halon's pull requests taught, and mark it strict. " \
                     "Admins hold it, and so do an incident's lead for its lessons and whoever asked Halon for a pull request for its " \
                     "lessons, without a grant. A grant lets anyone decide on every lesson. No access takes the default away."
      }.freeze,
      LESSON_OVERRIDE => {
        title: "Override strict lessons",
        description: "Let a pull request through although a finding from a strict lesson stands, which clears its failing Halon review " \
                     "check. Admins and the owners of the services a pull request belongs to, as the catalog names them, hold it for " \
                     "that pull request without a grant. A grant lets anyone else override on any pull request. No access takes the default away."
      }.freeze,
      INVESTIGATIONS_CREATE => {
        title: "Ask Halon and start investigations",
        description: "Ask Halon in a chat, in Slack or over MCP, start an investigation, add to a running one and apply its fix. " \
                     "Members hold it without a grant. Granting it to a member, alone or in a set, means the grant decides, " \
                     "so an expired grant leaves them none. No access takes it away at once."
      }.freeze,
      WORKFLOWS_CREATE => {
        title: "Make workflows",
        description: "Make a workflow's draft, from scratch, Firefight's library, a file or by asking Halon, test it and run one that is " \
                     "published. Members hold it without a grant. Granting it to a member, alone or in a set, means the grant decides, " \
                     "so an expired grant leaves them none. No access takes it away at once. Publishing a workflow is an admin's."
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

    # How much a change risks, which decides whether Halon asks before it in a chat. A safe change is harmless or put back
    # by another tool and touches no data, access, money or where production traffic goes, so Halon makes it without asking
    # while the workspace lets it and says so after. Anything else is risky and asks. A tool's class is its provider's
    # (Integrations::SafeChanges), and Firefight's own is safe for a write it can take back that asks no person.
    CHANGE_SAFE = "safe"
    CHANGE_RISKY = "risky"
    CHANGE_CLASSES = [ CHANGE_SAFE, CHANGE_RISKY ].freeze

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

    # Who may do what, the principals and tokens that carry it, the approvals that decide it and where events are sent.
    # A change to any of them is made only with a person's say. Halon asks on its card every time, and a call made with
    # a token or by a machine waits for a person to approve it (AbilityGateway.person_requirement).
    PERSON_CONFIRMED_RESOURCES = [ RESOURCE_PERMISSIONS, RESOURCE_API_KEYS, RESOURCE_APPROVALS, RESOURCE_WEBHOOKS ].freeze

    def self.asks_a_person?(resource, crud_action) = PERSON_CONFIRMED_RESOURCES.include?(resource.to_s) && crud_action.to_s != ACTION_READ

    # Firefight's own change to who may do what, or a connection's tool that changes access or a secret.
    def asks_a_person?
      return source.respond_to?(:access_change?) && source.access_change? if tool?

      system? && self.class.asks_a_person?(self.class.resource_of(key), key.to_s.split(".").last)
    end

    # An open action is never held, since a broad rule would stall every lookup. A workspace switches it off instead.
    def self.approval_exempt?(key)
      APPROVAL_EXEMPT_RESOURCES.include?(resource_of(key)) || open?(key)
    end
    # Nobody needs a grant for an open action, so none is offered.
    scope :grantable, -> { where.not(key: admin_only_keys + OPEN_KEYS) }
    scope :grantable_for, ->(workspace) { where(workspace_id: [ nil, workspace.id ]).grantable }

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

    # CHANGE_SAFE or CHANGE_RISKY for a change, nil for a read. params is the call, since a call shown to read is a read.
    def change_class(params = nil)
      return nil if risk_of(params) == RISK_READ

      safe = tool? ? source.respond_to?(:safe_change?) && source.safe_change? : risk_level == RISK_WRITE && reversible && !asks_a_person?
      safe ? CHANGE_SAFE : CHANGE_RISKY
    end

    def admin_only?
      system? && ADMIN_ONLY_RESOURCES.include?(self.class.resource_of(key))
    end

    # A tool action also needs whatever minted it wired for the scope. What
    # "wired" means belongs to the source, not the gateway.
    def configured_for?(scope)
      return true if system?

      source.present? && source.configured_for?(scope)
    end

    # The environment a call lands in: the one its scope names, or for a tool the environment of the row its connection
    # resolves without one, nil when that row is wired to no environment or none resolves.
    def environment_reached(scope)
      named = scope.to_h[Ability::Scope::DIMENSION_ENVIRONMENT] || scope.to_h[Ability::Scope::DIMENSION_ENVIRONMENT.to_sym]
      return named if named.present? || system? || source.nil?

      source.environment_reached
    end

    private

    def system_actions_are_global
      errors.add(:workspace_id, "must be blank for system actions") if system? && workspace_id.present?
      errors.add(:workspace_id, "is required for tool actions") if !system? && workspace_id.blank?
    end
  end
end
