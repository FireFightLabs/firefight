# Specialists read connected systems for Halon's chat, one kind of system each, so Halon's own tool list stays small and
# never changes during a chat. A specialist runs as a helper (Chat::Helpers), on its own thread and chat, reading only, as
# whoever the chat acts for, from the same purse. Which kind a connection's tools are comes from the provider registry
# (IntegrationProvider.specialist_for), so nothing here names a provider. Only a chat asks them, when its runner decides
# the turn should (ask?), and FirefightAi::Configuration#specialists can force it on or off.
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

  def self.mode = FirefightAi.configuration.specialists

  # Only a chat's own turn hands its reads to specialists, once its runner decided it should. A helper, a watch, a run,
  # the terminal and a held call keep reaching every tool as before.
  def self.for?(agent_run) = agent_run.is_a?(Conversation::Turn) && agent_run.asks_specialists?

  # Whether this turn asks specialists. In auto, only where the provider does not search tools itself, since there the
  # long tail already stays out of the model's context and out of the cached front until it is searched for, which is
  # what specialists are for. Elsewhere, only when some connection's reads would go to a specialist and the connections'
  # tools whoever asks may use, the long tail beyond Firefight's own, do not fit the held tools budget
  # (FirefightAi.chars_fit_up_front?). Firefight's own tools are counted out, since an admin holds more of them than a
  # member and a small workspace keeps today's way for both.
  # The decision reads a few columns of the connections' switched on tools, with their actions, and sums the length each
  # tool's row keeps (Integration::Tool#definition_chars), so the catalogue is built only when the turn is handed its
  # tools. It counts the tools the catalogue hands the turn ready to call: not a capability's, not a change on a turn that
  # only reads, and only one the asker's grants, read once, let them call.
  def self.ask?(turn, choice)
    case mode
    when FirefightAi::Configuration::SPECIALISTS_ON then true
    when FirefightAi::Configuration::SPECIALISTS_OFF then false
    else !FirefightAi.tool_search?(choice) && crowded?(turn)
    end
  end

  def self.crowded?(turn)
    principal = turn.acting_principal
    return false unless principal

    tools = Integration::Tool.switched_on_in(turn.workspace).select(:id, :integration_id, :name, :read_only, :definition_chars)
                             .preload(:integration, :ability_action).to_a
    reading = tools.select(&:read_only?).map(&:model_facing_name).to_set
    resolved = Chat::Tools.granted(turn)
    tail = tools.select do |tool|
      !Chat::Tools.through_capability?(tool) && !Chat::Tools.withheld_from?(turn, tool) && tool.callable_by?(principal, resolved)
    end
    tail.any? { |tool| of_provider(tool.integration.provider).present? && reading.include?(tool.model_facing_name) } &&
      !FirefightAi.chars_fit_up_front?(tail.sum(&:definition_chars))
  end

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

  # What Halon is told of a change a specialist proposed. Its report is outside text, like any tool result, so it never
  # backs a change on its own, and Look before you change counts only Halon's own reads.
  CONFIRM_FIRST = "A specialist's report is not enough to back a change. Before you propose it, confirm what it rests on " \
                  "with a read of your own in this turn, then load the tool by naming it in open_tools' tools, or by " \
                  "searching for it, and name your own reads in because.".freeze

  # A domain as Halon's ask_specialist lists it. connections names what it reads, state whether it can be asked.
  View = Data.define(:domain, :state, :connections) do
    def ready? = state == Chat::Tools::STATE_READY
  end
end
