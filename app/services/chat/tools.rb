# Everything the agent could reach, whoever is asking. A run or a conversation hands itself in, and
# the grants on its account decide which entries come back callable.
module Chat::Tools
  STATE_READY = :ready
  STATE_NOT_GRANTED = :not_granted
  STATE_NOT_CONNECTED = :not_connected

  Entry = Data.define(:name, :description, :state, :tool) do
    # How well this answers the question. Covering more of it counts for more than matching one
    # word twice, since a single common word like "incident" is in half the catalogue. Words are
    # compared singular, so "severities" answers "severity".
    def score(query)
      asked = terms(query)
      return 0 if asked.empty?

      in_name = asked & terms(name)
      covered = asked & (terms(name) + terms(description))
      (covered.size * 10) + in_name.size
    end

    def terms(text) = text.to_s.downcase.scan(/[a-z0-9]+/).map(&:singularize).to_set
  end

  # What a reader sees while the agent works. conclude and record_hypothesis are how it writes,
  # not what it looked at, so they are never shown.
  INTERNAL = %w[conclude record_hypothesis find_tools].freeze

  # The arguments that say what a step was about, in the order worth showing one of them.
  HEADLINE_ARGUMENTS = %w[query name identifier title].freeze
  ASKED_LIMIT = 60

  Step = Data.define(:title, :headline, :asked)

  # How a tool call reads to a person, live or saved. nil for the agent's own bookkeeping.
  def self.step(tool_name, arguments)
    return nil if tool_name.blank? || INTERNAL.include?(tool_name.to_s)

    asked = arguments.to_h.filter_map { |name, value| [ name.to_s, value.to_s.truncate(ASKED_LIMIT) ] if value.present? }
    headline = HEADLINE_ARGUMENTS.filter_map { |wanted| asked.assoc(wanted)&.last }.first.to_s
    Step.new(title: tool_name.to_s.tr("_", " ").humanize, headline: headline, asked: asked)
  end

  def self.catalog(agent_run)
    firefight_entries(agent_run) + connection_entries(agent_run) + unconnected_entries(agent_run)
  end

  def self.firefight_entries(agent_run)
    resolved = granted(agent_run)

    Mcp::Tools.all.map do |tool_class|
      resource, action = tool_class.authorization(agent_run.workspace, {})
      action_key = Ability::Action.system_key(resource, action)
      ready = resolved.action_keys.include?(action_key)
      Entry.new(
        name: tool_class.name_value, description: tool_class.description_value.to_s,
        state: ready ? STATE_READY : STATE_NOT_GRANTED,
        tool: (Firefight.new(agent_run, tool_class, action_key) if ready)
      )
    end
  end

  def self.connection_entries(agent_run)
    principal = agent_run.agent_principal
    resolved = granted(agent_run)

    Integration::Tool.in_workspace(agent_run.workspace).map do |tool|
      ready = tool.callable_by?(principal, resolved)
      Entry.new(
        name: tool.model_facing_name, description: tool.description.to_s,
        state: ready ? STATE_READY : STATE_NOT_GRANTED,
        tool: (Connection.new(agent_run, tool) if ready)
      )
    end
  end

  # Named so the agent can say a provider is not wired up rather than that it found nothing.
  def self.unconnected_entries(agent_run)
    connected = agent_run.workspace.integrations.active.pluck(:provider)

    IntegrationProvider.all.reject { |provider| connected.include?(provider.key) }.map do |provider|
      Entry.new(name: provider.name, description: provider.description, state: STATE_NOT_CONNECTED, tool: nil)
    end
  end

  def self.granted(agent_run)
    Ability::Resolver.resolve(agent_run.agent_principal, agent_run.workspace)
  end
end
