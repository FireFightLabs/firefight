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
  # What Halon raised on its own, and the module skills that say how it checks and what it does about a security event.
  MONITORING = "monitoring".freeze
  # The capabilities, which answer for anything on the resource map whichever provider holds it.
  RESOURCES = "resources".freeze
  # Systems outside the workspace's own: a provider's public status page, and the systems its apps use that nothing connects.
  OUTSIDE = "outside_systems".freeze
  # Posting as Firefight in a channel beyond an incident's own, such as release notes in #general.
  CHANNELS = "channels".freeze

  # Ways in for an outside agent. Halon does not ask itself a question, and a chat has its own start_investigation and
  # its own watches. Halon loads the workspace's skills with use_skill and proposes them with propose_skill, so a skill
  # never changes on its word alone.
  NOT_FOR_HALON = [
    FirefightTools::ASK_HALON, FirefightTools::GET_HALON_ANSWER, FirefightTools::START_INVESTIGATION, FirefightTools::LIST_WATCHES, FirefightTools::STOP_WATCH,
    FirefightTools::LIST_WORKFLOWS, FirefightTools::CREATE_WORKFLOW, FirefightTools::RUN_WORKFLOW,
    FirefightTools::LIST_SKILLS, FirefightTools::GET_SKILL, FirefightTools::UPSERT_SKILL, FirefightTools::DELETE_SKILL
  ].freeze

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
        FirefightTools::SEARCH_INCIDENTS, FirefightTools::SEARCH_SIMILAR, FirefightTools::GET_INCIDENT,
        FirefightTools::GET_INCIDENT_TRANSCRIPT, FirefightTools::GET_INVESTIGATION, FirefightTools::GET_HALON_PERFORMANCE
      ]
    ),
    Firefight.new(
      key: INCIDENT_RESPONSE, title: "Running an incident",
      covers: "declare, post an update, resolve, cancel, reopen, escalate, page whoever is on call, invite people, assign roles, link incidents",
      tools: [
        FirefightTools::DECLARE_INCIDENT, FirefightTools::POST_INCIDENT_UPDATE, FirefightTools::RESOLVE_INCIDENT,
        FirefightTools::CANCEL_INCIDENT, FirefightTools::REOPEN_INCIDENT, FirefightTools::ESCALATE_INCIDENT, FirefightTools::PAGE_ON_CALL,
        FirefightTools::INVITE_RESPONDERS, FirefightTools::ASSIGN_INCIDENT_ROLE, FirefightTools::LINK_INCIDENT,
        FirefightTools::GIVE_SHOUTOUT, FirefightTools::DISMISS_TIMELINE_NOTE
      ]
    ),
    Firefight.new(
      key: CHANNELS, title: "Posting in channels",
      covers: "post a message as Firefight in any channel it can post in, such as release notes in #general or a heads up to a " \
              "team, named by the channel's name or link",
      tools: [ FirefightTools::POST_TO_CHANNEL ]
    ),
    Firefight.new(
      key: FOLLOW_UPS, title: "Follow-ups and runbooks",
      covers: "action items, finding and reading runbooks, attaching one to an incident, claiming its steps",
      tools: [
        FirefightTools::CREATE_ACTION_ITEM, FirefightTools::ASSIGN_ACTION_ITEM, FirefightTools::COMPLETE_ACTION_ITEM,
        FirefightTools::RENAME_ACTION_ITEM, FirefightTools::REOPEN_ACTION_ITEM, FirefightTools::UNASSIGN_ACTION_ITEM,
        FirefightTools::CREATE_ACTION_ITEM_ISSUE, FirefightTools::SEARCH_RUNBOOKS, FirefightTools::GET_RUNBOOK, FirefightTools::ATTACH_RUNBOOK,
        FirefightTools::CLAIM_RUNBOOK_STEP, FirefightTools::UPSERT_RUNBOOK
      ]
    ),
    Firefight.new(
      key: POSTMORTEMS, title: "Postmortems",
      covers: "read one, start one, edit it, move it through review",
      tools: [
        FirefightTools::GET_POSTMORTEM, FirefightTools::START_POSTMORTEM, FirefightTools::UPDATE_POSTMORTEM,
        FirefightTools::SET_POSTMORTEM_STATUS
      ]
    ),
    Firefight.new(
      key: ALERTS, title: "Alerts and routing",
      covers: "search alerts, alert sources, routing rules and trying an alert against them",
      tools: [
        FirefightTools::SEARCH_ALERTS, FirefightTools::UPSERT_ALERT_SOURCE, FirefightTools::DELETE_ALERT_SOURCE,
        FirefightTools::EVALUATE_ROUTING, FirefightTools::UPSERT_ROUTING_RULE, FirefightTools::DELETE_ROUTING_RULE,
        FirefightTools::UPDATE_ROUTING_CONFIG
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
        FirefightTools::GET_RESOURCE_MAP, FirefightTools::SEARCH_MAP, FirefightTools::FIND_RESOURCES, FirefightTools::GET_RESOURCE, FirefightTools::GET_RESOURCE_LINKS,
        FirefightTools::GET_RESOURCE_NEIGHBOURS, FirefightTools::TRAVERSE_RESOURCE_MAP, FirefightTools::BLAST_RADIUS, FirefightTools::RESOURCE_MAP_STATS,
        FirefightTools::SUGGEST_RESOURCE_LINK
      ]
    ),
    Firefight.new(
      key: OUTSIDE, title: "Outside providers and what is not connected",
      covers: "read an outside provider's public status page now, such as a payment, email, sign-in, CDN or cloud provider, " \
              "when errors point at it, and find the systems the apps use that no connection reaches, with how to connect each",
      tools: [ FirefightTools::CHECK_STATUS_PAGE, FirefightTools::BLIND_SPOTS ]
    ),
    Firefight.new(
      key: MONITORING, title: "Monitoring and security",
      covers: "the problems Halon raised on its own from scheduled checks and security events, when it said each and whether it got " \
              "worse, and how to check disks, certificates, error budgets, cost, a leaked secret, credential stuffing and suspicious access",
      tools: [ FirefightTools::LIST_NOTICES ]
    ),
    Firefight.new(
      key: CATALOG, title: "Services, teams and ownership",
      covers: "search the catalog, who owns what, add or change entries and types",
      tools: [
        FirefightTools::SEARCH_CATALOG, FirefightTools::UPSERT_CATALOG_ENTRY, FirefightTools::DELETE_CATALOG_ENTRY,
        FirefightTools::UPSERT_CATALOG_TYPE, FirefightTools::DELETE_CATALOG_TYPE
      ]
    ),
    Firefight.new(
      key: SETUP, title: "Workspace setup",
      covers: "what is configured, the workspace settings, severities, statuses, incident types, roles, forms and custom fields, what can be connected, " \
              "the paths Halon may not change in a code host's repositories, a workflow's settings, and the handbook's pages when a person asks for them to change",
      tools: [
        FirefightTools::GET_WORKSPACE_CONFIG, FirefightTools::UPDATE_WORKSPACE_SETTINGS, FirefightTools::UPDATE_PROTECTED_PATHS, FirefightTools::LIST_INTEGRATIONS, FirefightTools::UPSERT_SEVERITY, FirefightTools::DELETE_SEVERITY,
        FirefightTools::UPSERT_STATUS, FirefightTools::DELETE_STATUS, FirefightTools::UPSERT_INCIDENT_TYPE,
        FirefightTools::DELETE_INCIDENT_TYPE, FirefightTools::UPSERT_INCIDENT_ROLE, FirefightTools::DELETE_INCIDENT_ROLE,
        FirefightTools::GET_FORM, FirefightTools::UPSERT_FORM_FIELD, FirefightTools::UPSERT_CUSTOM_FIELD,
        FirefightTools::LIST_HANDBOOK_PAGES, FirefightTools::GET_HANDBOOK_PAGE, FirefightTools::UPSERT_HANDBOOK_PAGE, FirefightTools::DELETE_HANDBOOK_PAGE,
        FirefightTools::UPDATE_WORKFLOW_SETTINGS, FirefightTools::UPDATE_WORKFLOW
      ]
    ),
    Firefight.new(
      key: PERMISSIONS, title: "Permissions and approvals",
      covers: "who may do what, what members can read and change in each tool, permission sets, grants, approval rules, unattended rules, what Halon may do without asking, pending approvals, the activity log",
      tools: [
        FirefightTools::LIST_ABILITIES, FirefightTools::LIST_PRINCIPALS, FirefightTools::UPSERT_PERMISSION_SET,
        FirefightTools::DELETE_PERMISSION_SET, FirefightTools::GRANT_ABILITY, FirefightTools::REVOKE_GRANT,
        FirefightTools::LIST_MEMBER_ACCESS, FirefightTools::SET_MEMBER_ACCESS,
        FirefightTools::UPSERT_APPROVAL_RULE, FirefightTools::DELETE_APPROVAL_RULE, FirefightTools::LIST_UNATTENDED_RULES,
        FirefightTools::UPSERT_UNATTENDED_RULE, FirefightTools::DELETE_UNATTENDED_RULE, FirefightTools::LIST_ALLOWANCES,
        FirefightTools::UPSERT_ALLOWANCE, FirefightTools::DELETE_ALLOWANCE, FirefightTools::SEARCH_APPROVALS,
        FirefightTools::APPROVE_APPROVAL, FirefightTools::DENY_APPROVAL, FirefightTools::SEARCH_ACTIVITY
      ]
    ),
    Firefight.new(
      key: ACCESS, title: "Agents, API keys and Firefight outbound webhooks",
      covers: "machine accounts and their tokens, API keys, and Firefight's own outbound webhooks, which post this " \
              "workspace's incident events to a URL the team owns. Never a provider's webhooks, such as a deploy or " \
              "workflow trigger at a hosting provider or a code host's webhooks, which that provider's own tools reach",
      tools: [
        FirefightTools::LIST_AGENTS, FirefightTools::UPSERT_AGENT, FirefightTools::ROTATE_AGENT_TOKEN,
        FirefightTools::REVOKE_AGENT_TOKEN, FirefightTools::DELETE_AGENT, FirefightTools::LIST_API_KEYS,
        FirefightTools::UPSERT_API_KEY, FirefightTools::DELETE_API_KEY, FirefightTools::UPSERT_OUTBOUND_WEBHOOK,
        FirefightTools::DELETE_OUTBOUND_WEBHOOK, FirefightTools::TEST_OUTBOUND_WEBHOOK
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
