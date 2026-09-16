# Everything the agent could reach, whoever is asking. A run or a conversation hands itself in, and
# the grants on its account decide which entries come back callable.
module Chat::Tools
  STATE_READY = :ready
  STATE_NOT_GRANTED = :not_granted
  STATE_NOT_CONNECTED = :not_connected

  Entry = Data.define(:name, :description, :state, :tool) do
    def matches?(query)
      words = query.to_s.downcase.scan(/[a-z0-9]+/)
      return false if words.empty?

      haystack = "#{name} #{description}".downcase
      words.any? { |word| haystack.include?(word) }
    end
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
