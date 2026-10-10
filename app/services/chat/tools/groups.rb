# The map the agent reads to find its tools. A group is the question its tools answer, never the
# vendor behind them, so the agent can ask for logs without knowing which provider a workspace uses.
module Chat::Tools::Groups
  INCIDENT_HISTORY = "incident_history".freeze
  INCIDENT_RESPONSE = "incident_response".freeze
  FOLLOW_UPS = "follow_ups".freeze
  POSTMORTEMS = "postmortems".freeze
  ALERTS = "alerts".freeze
  CATALOG = "catalog".freeze
  # The resource map itself, for where things run, how they depend on each other and what fails with one.
  MAP = "resource_map".freeze
  SETUP = "workspace_setup".freeze
  PERMISSIONS = "permissions".freeze
  ACCESS = "machine_access".freeze
  # The capabilities, which answer for anything on the resource map whichever provider holds it.
  RESOURCES = "resources".freeze
  # Systems outside the workspace's own: a provider's public status page, and the systems its apps use that nothing connects.
  OUTSIDE = "outside_systems".freeze

  # Ways in for an outside agent. Halon does not ask itself a question, and a chat has its own start_investigation and
  # its own watches.
  NOT_FOR_HALON = [ Mcp::Tools::ASK_HALON, Mcp::Tools::START_INVESTIGATION, Mcp::Tools::LIST_WATCHES, Mcp::Tools::STOP_WATCH ].freeze

  # The registry's catch all, whose connections have nothing in common but their kind.
  CUSTOM_CATEGORY = "Custom".freeze
  CONNECTION_PREFIX = "connection_".freeze
  NAMES_SHOWN = 8

  Firefight = Data.define(:key, :title, :covers, :tools)

  # Every tool Firefight has sits in exactly one of these, which a test holds, so a new tool cannot be left unreachable.
  FIREFIGHT = [
    Firefight.new(
      key: INCIDENT_HISTORY, title: "Incidents and what happened before",
      covers: "search incidents, find ones that read like this, read one, what was said in its channel, past investigations, how accurate Halon has been",
      tools: [
        Mcp::Tools::SEARCH_INCIDENTS, Mcp::Tools::SEARCH_SIMILAR, Mcp::Tools::GET_INCIDENT,
        Mcp::Tools::GET_INCIDENT_TRANSCRIPT, Mcp::Tools::GET_INVESTIGATION, Mcp::Tools::GET_HALON_PERFORMANCE
      ]
    ),
    Firefight.new(
      key: INCIDENT_RESPONSE, title: "Running an incident",
      covers: "declare, post an update, resolve, cancel, reopen, escalate, invite people, assign roles, link incidents",
      tools: [
        Mcp::Tools::DECLARE_INCIDENT, Mcp::Tools::POST_INCIDENT_UPDATE, Mcp::Tools::RESOLVE_INCIDENT,
        Mcp::Tools::CANCEL_INCIDENT, Mcp::Tools::REOPEN_INCIDENT, Mcp::Tools::ESCALATE_INCIDENT,
        Mcp::Tools::INVITE_RESPONDERS, Mcp::Tools::ASSIGN_INCIDENT_ROLE, Mcp::Tools::LINK_INCIDENT,
        Mcp::Tools::GIVE_SHOUTOUT, Mcp::Tools::DISMISS_TIMELINE_NOTE
      ]
    ),
    Firefight.new(
      key: FOLLOW_UPS, title: "Follow-ups and runbooks",
      covers: "action items, finding and reading runbooks, attaching one to an incident, claiming its steps",
      tools: [
        Mcp::Tools::CREATE_ACTION_ITEM, Mcp::Tools::ASSIGN_ACTION_ITEM, Mcp::Tools::COMPLETE_ACTION_ITEM,
        Mcp::Tools::RENAME_ACTION_ITEM, Mcp::Tools::REOPEN_ACTION_ITEM, Mcp::Tools::UNASSIGN_ACTION_ITEM,
        Mcp::Tools::CREATE_ACTION_ITEM_ISSUE, Mcp::Tools::SEARCH_RUNBOOKS, Mcp::Tools::GET_RUNBOOK, Mcp::Tools::ATTACH_RUNBOOK,
        Mcp::Tools::CLAIM_RUNBOOK_STEP, Mcp::Tools::UPSERT_RUNBOOK
      ]
    ),
    Firefight.new(
      key: POSTMORTEMS, title: "Postmortems",
      covers: "read one, start one, edit it, move it through review",
      tools: [
        Mcp::Tools::GET_POSTMORTEM, Mcp::Tools::START_POSTMORTEM, Mcp::Tools::UPDATE_POSTMORTEM,
        Mcp::Tools::SET_POSTMORTEM_STATUS
      ]
    ),
    Firefight.new(
      key: ALERTS, title: "Alerts and routing",
      covers: "search alerts, alert sources, routing rules and trying an alert against them",
      tools: [
        Mcp::Tools::SEARCH_ALERTS, Mcp::Tools::UPSERT_ALERT_SOURCE, Mcp::Tools::DELETE_ALERT_SOURCE,
        Mcp::Tools::EVALUATE_ROUTING, Mcp::Tools::UPSERT_ROUTING_RULE, Mcp::Tools::DELETE_ROUTING_RULE,
        Mcp::Tools::UPDATE_ROUTING_CONFIG
      ]
    ),
    Firefight.new(
      key: MAP, title: "The resource map",
      covers: "read off the connections, for where something runs and which provider and account hold it, then find resources by " \
              "filter, or search them with the catalog and confirmed memories by a name, an id or what a service does, read one, " \
              "its links and neighbours, walk what it depends on or what depends on it, what fails with it, the map in numbers, " \
              "what changed around a resource, a service or the whole workspace (deploys, runs, settings, hand edits and changes " \
              "made through Firefight, in one list), and suggest a link",
      tools: [
        Mcp::Tools::GET_RESOURCE_MAP, Mcp::Tools::SEARCH_MAP, Mcp::Tools::FIND_RESOURCES, Mcp::Tools::GET_RESOURCE, Mcp::Tools::GET_RESOURCE_LINKS,
        Mcp::Tools::GET_RESOURCE_NEIGHBOURS, Mcp::Tools::TRAVERSE_RESOURCE_MAP, Mcp::Tools::BLAST_RADIUS, Mcp::Tools::RESOURCE_MAP_STATS,
        Mcp::Tools::SUGGEST_RESOURCE_LINK
      ]
    ),
    Firefight.new(
      key: OUTSIDE, title: "Outside providers and what is not connected",
      covers: "read an outside provider's public status page now, such as a payment, email, sign-in, CDN or cloud provider, " \
              "when errors point at it, and find the systems the apps use that no connection reaches, with how to connect each",
      tools: [ Mcp::Tools::CHECK_STATUS_PAGE, Mcp::Tools::BLIND_SPOTS ]
    ),
    Firefight.new(
      key: CATALOG, title: "Services, teams and ownership",
      covers: "search the catalog, who owns what, add or change entries and types",
      tools: [
        Mcp::Tools::SEARCH_CATALOG, Mcp::Tools::UPSERT_CATALOG_ENTRY, Mcp::Tools::DELETE_CATALOG_ENTRY,
        Mcp::Tools::UPSERT_CATALOG_TYPE, Mcp::Tools::DELETE_CATALOG_TYPE
      ]
    ),
    Firefight.new(
      key: SETUP, title: "Workspace setup",
      covers: "what is configured, the workspace settings, severities, statuses, incident types, roles, forms and custom fields, what can be connected, " \
              "and the paths Halon may not change in a code host's repositories",
      tools: [
        Mcp::Tools::GET_WORKSPACE_CONFIG, Mcp::Tools::UPDATE_WORKSPACE_SETTINGS, Mcp::Tools::UPDATE_PROTECTED_PATHS, Mcp::Tools::LIST_INTEGRATIONS, Mcp::Tools::UPSERT_SEVERITY, Mcp::Tools::DELETE_SEVERITY,
        Mcp::Tools::UPSERT_STATUS, Mcp::Tools::DELETE_STATUS, Mcp::Tools::UPSERT_INCIDENT_TYPE,
        Mcp::Tools::DELETE_INCIDENT_TYPE, Mcp::Tools::UPSERT_INCIDENT_ROLE, Mcp::Tools::DELETE_INCIDENT_ROLE,
        Mcp::Tools::GET_FORM, Mcp::Tools::UPSERT_FORM_FIELD, Mcp::Tools::UPSERT_CUSTOM_FIELD
      ]
    ),
    Firefight.new(
      key: PERMISSIONS, title: "Permissions and approvals",
      covers: "who may do what, permission sets, grants, approval rules, unattended rules, pending approvals, the activity log",
      tools: [
        Mcp::Tools::LIST_ABILITIES, Mcp::Tools::LIST_PRINCIPALS, Mcp::Tools::UPSERT_PERMISSION_SET,
        Mcp::Tools::DELETE_PERMISSION_SET, Mcp::Tools::GRANT_ABILITY, Mcp::Tools::REVOKE_GRANT,
        Mcp::Tools::UPSERT_APPROVAL_RULE, Mcp::Tools::DELETE_APPROVAL_RULE, Mcp::Tools::LIST_UNATTENDED_RULES,
        Mcp::Tools::UPSERT_UNATTENDED_RULE, Mcp::Tools::DELETE_UNATTENDED_RULE, Mcp::Tools::SEARCH_APPROVALS,
        Mcp::Tools::APPROVE_APPROVAL, Mcp::Tools::DENY_APPROVAL, Mcp::Tools::SEARCH_ACTIVITY
      ]
    ),
    Firefight.new(
      key: ACCESS, title: "Agents, API keys and Firefight outbound webhooks",
      covers: "machine accounts and their tokens, API keys, and Firefight's own outbound webhooks, which post this " \
              "workspace's incident events to a URL the team owns. Never a provider's webhooks, such as a deploy or " \
              "workflow trigger at a hosting provider or a code host's webhooks, which that provider's own tools reach",
      tools: [
        Mcp::Tools::LIST_AGENTS, Mcp::Tools::UPSERT_AGENT, Mcp::Tools::ROTATE_AGENT_TOKEN,
        Mcp::Tools::REVOKE_AGENT_TOKEN, Mcp::Tools::DELETE_AGENT, Mcp::Tools::LIST_API_KEYS,
        Mcp::Tools::UPSERT_API_KEY, Mcp::Tools::DELETE_API_KEY, Mcp::Tools::UPSERT_OUTBOUND_WEBHOOK,
        Mcp::Tools::DELETE_OUTBOUND_WEBHOOK, Mcp::Tools::TEST_OUTBOUND_WEBHOOK
      ]
    )
  ].freeze

  # connected names the connections behind a group, which can be there with every tool switched off, and idle those of
  # them with no tool switched on, as a person tells them apart, even while the others' tools are on.
  View = Data.define(:key, :title, :covers, :entries, :could_connect, :connected, :idle) do
    def initialize(key:, title:, covers:, entries:, could_connect: [], connected: [], idle: []) = super

    def state
      return Chat::Tools::STATE_READY if entries.any?(&:tool)
      return Chat::Tools::STATE_READS_ONLY if entries.any? && entries.all? { |entry| entry.state == Chat::Tools::STATE_READS_ONLY }
      return Chat::Tools::STATE_NOT_GRANTED if entries.any?

      connected.any? ? Chat::Tools::STATE_SWITCHED_OFF : Chat::Tools::STATE_NOT_CONNECTED
    end
  end

  def self.of_firefight_tool(name)
    FIREFIGHT.find { |group| group.tools.include?(name.to_s) }&.key
  end

  # A provider in the registry answers the question its category names. Anything else is its own group.
  def self.of_connection(integration)
    category = IntegrationProvider.find(integration.provider)&.category
    return "#{CONNECTION_PREFIX}#{integration.slug}" if category.blank? || category == CUSTOM_CATEGORY

    category_key(category)
  end

  def self.category_key(category) = IntegrationProvider.category_slug(category)

  def self.for(agent_run)
    entries = Chat::Tools.catalog(agent_run).group_by(&:group)
    integrations = agent_run.workspace.integrations.active.includes(:tools).order(:created_at).to_a

    firefight_views(entries) + resource_views(entries) + category_views(entries, integrations) + connection_views(entries, integrations)
  end

  def self.resource_views(entries)
    found = entries.fetch(RESOURCES, [])
    return [] if found.empty?

    [ View.new(key: RESOURCES, title: "Anything on the resource map",
               covers: "#{found.map(&:name).join(', ')}, for a service, database, function or site by its name on the map, whichever connection runs it",
               entries: found) ]
  end

  def self.firefight_views(entries)
    FIREFIGHT.map do |group|
      View.new(key: group.key, title: group.title, covers: group.covers, entries: entries.fetch(group.key, []))
    end
  end

  def self.category_views(entries, integrations)
    IntegrationProvider.category_list.reject { |each| each.name == CUSTOM_CATEGORY }.map do |listed|
      category = listed.name
      tagline = listed.group_line
      key = category_key(category)
      behind = integrations.select { |integration| of_connection(integration) == key }
      connected = behind.map(&:name)
      idle = idle(behind)
      covers = connected.any? ? "#{tagline}, through #{connected.to_sentence}" : tagline
      covers += ", though #{idle.to_sentence} #{idle.one? ? 'has' : 'have'} no tools switched on" if idle.any? && idle.size < behind.size
      offered = IntegrationProvider.all.select { |provider| provider.category == category }.map(&:name)
      View.new(key: key, title: category, covers: covers, entries: entries.fetch(key, []), could_connect: offered, connected: connected, idle: idle)
    end
  end

  # The connections with no tool switched on, as a person tells them apart.
  def self.idle(integrations)
    integrations.reject { |integration| integration.tools.any? { |tool| tool.enabled? && tool.available? } }
                .map { |integration| Chat::Tools.clean(integration.display_name, Chat::Tools::TITLE_LIMIT) }
  end

  # The admin's own name for it, and its tools' names, since what such a server says about itself is not ours to trust.
  def self.connection_views(entries, integrations)
    integrations.filter_map do |integration|
      key = of_connection(integration)
      next unless key.start_with?(CONNECTION_PREFIX)

      names = integration.tools.select { |tool| tool.enabled? && tool.available? }.map(&:name).sort
      covers = names.first(NAMES_SHOWN).join(", ")
      covers += " and #{names.size - NAMES_SHOWN} more" if names.size > NAMES_SHOWN
      View.new(
        key: key, title: Chat::Tools.clean(integration.name, Chat::Tools::TITLE_LIMIT),
        covers: Chat::Tools.clean(covers, Chat::Tools::ONE_LINE), entries: entries.fetch(key, []),
        connected: [ Chat::Tools.clean(integration.name, Chat::Tools::TITLE_LIMIT) ]
      )
    end
  end
end
