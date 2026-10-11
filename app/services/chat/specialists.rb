# Specialists read connected systems for Halon's chat, one kind of system each, so Halon's own tool list stays small and
# never changes during a chat. A specialist runs as a helper (Chat::Helpers), on its own thread and chat, reading only, as
# whoever the chat acts for, from the same purse. Which kind a connection's tools are comes from the provider registry
# (IntegrationProvider.specialist_for), so nothing here names a provider. Off unless the deployment turns it on
# (FirefightAi::Configuration#specialists), and only a chat asks them.
module Chat::Specialists
  CODE = "code".freeze
  DEPLOYS = "deploys".freeze
  OBSERVABILITY = "observability".freeze
  DATABASES = "databases".freeze
  CLOUD = "cloud".freeze
  TICKETS = "tickets".freeze
  ON_CALL = "on_call".freeze

  # One kind of question a specialist answers. covers is what Halon reads when choosing one, practice how it reads,
  # playbook the name of Halon's playbook for the same work, capabilities the capabilities and general reads it holds
  # beside its connections' tools, firefight_reads Firefight's own reads that help it find its way, and changes the
  # capabilities that change something which it may propose beside its connections' own.
  Domain = Data.define(:key, :title, :covers, :practice, :playbook, :capabilities, :firefight_reads, :changes) do
    def initialize(changes: [], **) = super
  end

  # Where a resource runs and which account and repository hold it, which every kind of question starts from.
  MAP_READS = [ Mcp::Tools::GET_RESOURCE_MAP, Mcp::Tools::SEARCH_MAP, Mcp::Tools::FIND_RESOURCES, Mcp::Tools::GET_RESOURCE, Mcp::Tools::GET_RESOURCE_LINKS ].freeze

  def self.capability(key) = Integrations::Capabilities.spec(key).tool_name

  DOMAINS = [
    Domain.new(
      key: CODE, title: "Code",
      covers: "repositories, commits, pull requests, branches, files, blame and the code a change touched, on the connected code hosts",
      practice: "Read the code at the commit that is running, not only the default branch. Name each file with its lines and each commit by its short id.",
      playbook: "code", capabilities: [ ResourceMap::Timeline::TOOL_NAME ], firefight_reads: []
    ),
    Domain.new(
      key: DEPLOYS, title: "Deploys and runs",
      covers: "where apps run, their deployments, settings and environment, builds, CI and pipeline runs with their logs, and what changed",
      practice: "Line deploys and runs up with when the trouble started. A setting changed by a deploy shows only in the provider's own record of it, so read that record.",
      playbook: "deploying",
      capabilities: [ capability(Integrations::Capabilities::DEPLOYS), capability(Integrations::Capabilities::HISTORY),
                      capability(Integrations::Capabilities::STATUS), ResourceMap::Timeline::TOOL_NAME ],
      firefight_reads: [],
      changes: [ capability(Integrations::Capabilities::ROLLBACK), capability(Integrations::Capabilities::RESTART), capability(Integrations::Capabilities::SCALE) ]
    ),
    Domain.new(
      key: OBSERVABILITY, title: "Logs, metrics and traces",
      covers: "logs, metrics, traces, errors and product analytics, what is new and since when",
      practice: "Compare with a normal window before calling something new. Count how often each error appears and when it first did.",
      playbook: "monitoring",
      capabilities: [ capability(Integrations::Capabilities::LOGS), capability(Integrations::Capabilities::METRICS),
                      capability(Integrations::Capabilities::ERRORS), capability(Integrations::Capabilities::TRACES),
                      capability(Integrations::Capabilities::STATUS), Integrations::Capabilities::KEY_QUERY_TOOL,
                      Integrations::Capabilities::LOG_PATTERNS_TOOL ],
      firefight_reads: []
    ),
    Domain.new(
      key: DATABASES, title: "Databases",
      covers: "database health, connections and who holds them, locks, slow queries, replication, schemas and read only queries of the data",
      practice: "Read the primary first. Count before you judge, and read who holds the connections and the locks.",
      playbook: "data",
      capabilities: [ capability(Integrations::Capabilities::STATUS), capability(Integrations::Capabilities::METRICS), Integrations::Capabilities::KEY_QUERY_TOOL ],
      firefight_reads: []
    ),
    Domain.new(
      key: CLOUD, title: "Cloud resources and cost",
      covers: "cloud accounts and their resources, networking, DNS, quotas, limits and the bill",
      practice: "Name the account, region and resource of everything you report. For cost, compare with the same window before.",
      playbook: "capacity", capabilities: [ capability(Integrations::Capabilities::STATUS), capability(Integrations::Capabilities::METRICS) ],
      firefight_reads: []
    ),
    Domain.new(
      key: TICKETS, title: "Tickets and docs",
      covers: "issues, tickets and follow-up work, the team's knowledge pages, runbooks and the handbook",
      practice: "Quote the ticket or page you rely on, with its link. Say how old a page is when that matters.",
      playbook: nil, capabilities: [],
      firefight_reads: [ Mcp::Tools::SEARCH_RUNBOOKS, Mcp::Tools::GET_RUNBOOK, Mcp::Tools::LIST_HANDBOOK_PAGES, Mcp::Tools::GET_HANDBOOK_PAGE ]
    ),
    Domain.new(
      key: ON_CALL, title: "On-call and alerts",
      covers: "who is on call, schedules, pages and acknowledgements, and the alerts behind them",
      practice: "Say who was paged, when, by which alert, and whether they acknowledged.",
      playbook: "incident_command", capabilities: [],
      firefight_reads: [ Mcp::Tools::SEARCH_ALERTS, Mcp::Tools::GET_INCIDENT, Mcp::Tools::SEARCH_INCIDENTS ]
    )
  ].freeze
  KEYS = DOMAINS.map(&:key).freeze

  def self.domain(key) = DOMAINS.find { |each| each.key == key.to_s }

  def self.on? = FirefightAi.configuration.specialists == true

  # Only a chat's own turn hands its reads to specialists. A helper, a watch, a run, the terminal and a held call keep
  # reaching every tool as before.
  def self.for?(agent_run) = on? && agent_run.is_a?(Conversation::Turn)

  # The kind a connection's provider answers, from the registry, or nil for one that stays Halon's own.
  def self.of_provider(provider_key) = IntegrationProvider.specialist_for(provider_key)

  # A connection tool that only reads and whose provider a specialist reads is the specialist's, so Halon is never handed
  # it. A tool that can change something stays Halon's to load, and a connection no specialist reads stays Halon's own.
  def self.reserved?(workspace, entry)
    entry.source != Chat::Skill::SOURCE_FIREFIGHT && of_provider(entry.source).present? && workspace.reading_tool_names.include?(entry.name.to_s)
  end

  # The kinds a Firefight tool or capability helps, by its name, whether it reads or is a change one may propose.
  def self.helping(name)
    named = name.to_s
    DOMAINS.select { |each| (each.capabilities + each.firefight_reads + each.changes + MAP_READS).include?(named) }.map(&:key)
  end

  # How a specialist of this kind reads, with Halon's playbook for the same work when there is one.
  def self.instructions(domain)
    playbook = domain.playbook && Chat::Skill.find(domain.playbook)
    [ "Your kind of system: #{domain.title}, which covers #{domain.covers}.", domain.practice,
      ("The playbook for this work, for what good looks like:\n#{playbook.steps}" if playbook) ].compact.join("\n\n")
  end

  # A change a specialist may propose, by the name Halon calls it and one line on what it does.
  Change = Data.define(:name, :line)

  # One change a specialist proposed: the tool, its arguments, the reads behind it and how to undo it.
  Proposal = Data.define(:tool, :arguments, :because, :undo) do
    def self.from(hash)
      given = hash.to_h.stringify_keys
      new(tool: given["tool"].to_s, arguments: given["arguments"].to_h, because: Array(given["because"]).map(&:to_s), undo: given["undo"].to_s.presence)
    end

    def to_h = { "tool" => tool, "arguments" => arguments, "because" => because, "undo" => undo }.compact
  end

  # What putting a proposed change's tool in Halon's hands said, by the tool's name.
  Loaded = Data.define(:name, :said)

  # A domain as Halon's ask_specialist lists it. connections names what it reads, state whether it can be asked.
  View = Data.define(:domain, :state, :connections) do
    def ready? = state == Chat::Tools::STATE_READY
  end
end
