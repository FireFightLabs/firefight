# The map the agent reads to find its tools. A group is the question its tools answer, never the
# vendor behind them, so the agent can ask for logs without knowing which provider a workspace uses.
module Chat::Tools::Groups
  INCIDENT_HISTORY = "incident_history".freeze
  INCIDENT_RESPONSE = "incident_response".freeze
  FOLLOW_UPS = "follow_ups".freeze
  POSTMORTEMS = "postmortems".freeze
  ALERTS = "alerts".freeze
  CATALOG = "catalog".freeze
  SETUP = "workspace_setup".freeze
  PERMISSIONS = "permissions".freeze
  ACCESS = "machine_access".freeze

  # The registry's catch all, whose connections have nothing in common but their kind.
  CUSTOM_CATEGORY = "Custom".freeze
  CONNECTION_PREFIX = "connection_".freeze
  NAMES_SHOWN = 8

  Firefight = Data.define(:key, :title, :covers, :tools)

  # Every tool Firefight has sits in exactly one of these, which a test holds, so a new tool cannot be left unreachable.
  FIREFIGHT = [
    Firefight.new(
      key: INCIDENT_HISTORY, title: "Incidents and what happened before",
      covers: "search incidents, find ones that read like this, read one and what was said in its channel",
      tools: [ Mcp::Tools::SEARCH_INCIDENTS, Mcp::Tools::SEARCH_SIMILAR, Mcp::Tools::GET_INCIDENT, Mcp::Tools::GET_INCIDENT_TRANSCRIPT ]
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
        Mcp::Tools::SEARCH_RUNBOOKS, Mcp::Tools::GET_RUNBOOK, Mcp::Tools::ATTACH_RUNBOOK,
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
      key: CATALOG, title: "Services, teams and ownership",
      covers: "search the catalog, who owns what, add or change entries and types",
      tools: [
        Mcp::Tools::SEARCH_CATALOG, Mcp::Tools::UPSERT_CATALOG_ENTRY, Mcp::Tools::DELETE_CATALOG_ENTRY,
        Mcp::Tools::UPSERT_CATALOG_TYPE, Mcp::Tools::DELETE_CATALOG_TYPE
      ]
    ),
    Firefight.new(
      key: SETUP, title: "Workspace setup",
      covers: "what is configured, severities, statuses, incident types, roles, forms and custom fields",
      tools: [
        Mcp::Tools::GET_WORKSPACE_CONFIG, Mcp::Tools::UPSERT_SEVERITY, Mcp::Tools::DELETE_SEVERITY,
        Mcp::Tools::UPSERT_STATUS, Mcp::Tools::DELETE_STATUS, Mcp::Tools::UPSERT_INCIDENT_TYPE,
        Mcp::Tools::DELETE_INCIDENT_TYPE, Mcp::Tools::UPSERT_INCIDENT_ROLE, Mcp::Tools::DELETE_INCIDENT_ROLE,
        Mcp::Tools::GET_FORM, Mcp::Tools::UPSERT_FORM_FIELD, Mcp::Tools::UPSERT_CUSTOM_FIELD
      ]
    ),
    Firefight.new(
      key: PERMISSIONS, title: "Permissions and approvals",
      covers: "who may do what, permission sets, grants, approval rules, pending approvals, the activity log",
      tools: [
        Mcp::Tools::LIST_ABILITIES, Mcp::Tools::LIST_PRINCIPALS, Mcp::Tools::UPSERT_PERMISSION_SET,
        Mcp::Tools::DELETE_PERMISSION_SET, Mcp::Tools::GRANT_ABILITY, Mcp::Tools::REVOKE_GRANT,
        Mcp::Tools::UPSERT_APPROVAL_RULE, Mcp::Tools::DELETE_APPROVAL_RULE, Mcp::Tools::SEARCH_APPROVALS,
        Mcp::Tools::APPROVE_APPROVAL, Mcp::Tools::DENY_APPROVAL, Mcp::Tools::SEARCH_ACTIVITY
      ]
    ),
    Firefight.new(
      key: ACCESS, title: "Agents, API keys and webhooks",
      covers: "machine accounts and their tokens, API keys, outbound webhooks",
      tools: [
        Mcp::Tools::LIST_AGENTS, Mcp::Tools::UPSERT_AGENT, Mcp::Tools::ROTATE_AGENT_TOKEN,
        Mcp::Tools::REVOKE_AGENT_TOKEN, Mcp::Tools::DELETE_AGENT, Mcp::Tools::LIST_API_KEYS,
        Mcp::Tools::UPSERT_API_KEY, Mcp::Tools::DELETE_API_KEY, Mcp::Tools::UPSERT_WEBHOOK,
        Mcp::Tools::DELETE_WEBHOOK, Mcp::Tools::TEST_WEBHOOK
      ]
    )
  ].freeze

  View = Data.define(:key, :title, :covers, :entries, :could_connect) do
    def state
      return Chat::Tools::STATE_NOT_CONNECTED if entries.empty?

      entries.any?(&:tool) ? Chat::Tools::STATE_READY : Chat::Tools::STATE_NOT_GRANTED
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

  def self.category_key(category) = category.parameterize(separator: "_")

  def self.for(agent_run)
    entries = Chat::Tools.catalog(agent_run).group_by(&:group)
    integrations = agent_run.workspace.integrations.active.to_a

    firefight_views(entries) + category_views(entries, integrations) + connection_views(entries, integrations)
  end

  def self.firefight_views(entries)
    FIREFIGHT.map do |group|
      View.new(key: group.key, title: group.title, covers: group.covers, entries: entries.fetch(group.key, []), could_connect: [])
    end
  end

  def self.category_views(entries, integrations)
    IntegrationProvider.categories.except(CUSTOM_CATEGORY).map do |category, tagline|
      key = category_key(category)
      connected = integrations.select { |integration| of_connection(integration) == key }.map(&:name)
      covers = connected.any? ? "#{tagline}, through #{connected.to_sentence}" : tagline
      offered = IntegrationProvider.all.select { |provider| provider.category == category }.map(&:name)
      View.new(key: key, title: category, covers: covers, entries: entries.fetch(key, []), could_connect: offered)
    end
  end

  # The admin's own name for it, and its tools' names, since what such a server says about itself is not ours to trust.
  def self.connection_views(entries, integrations)
    integrations.filter_map do |integration|
      key = of_connection(integration)
      next unless key.start_with?(CONNECTION_PREFIX)

      names = integration.tools.enabled.available.order(:name).pluck(:name)
      covers = names.first(NAMES_SHOWN).join(", ")
      covers += " and #{names.size - NAMES_SHOWN} more" if names.size > NAMES_SHOWN
      View.new(
        key: key, title: Chat::Tools.clean(integration.name, Chat::Tools::TITLE_LIMIT),
        covers: Chat::Tools.clean(covers, Chat::Tools::ONE_LINE), entries: entries.fetch(key, []), could_connect: []
      )
    end
  end
end
