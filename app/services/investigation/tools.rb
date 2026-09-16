# What the agent may call during a run. Only the three it always needs are handed over. Everything
# else it finds with find_tools, which is also how it learns that something exists but is not granted.
module Investigation::Tools
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

  def self.for(investigation, offer:)
    [ Find.new(investigation, offer: offer), RecordHypothesis.new(investigation), Conclude.new(investigation) ]
  end

  def self.catalog(investigation)
    firefight_entries(investigation) + connection_entries(investigation) + unconnected_entries(investigation)
  end

  def self.firefight_entries(investigation)
    resolved = granted(investigation)

    Mcp::Tools.all.map do |tool_class|
      resource, action = tool_class.authorization(investigation.workspace, {})
      action_key = Ability::Action.system_key(resource, action)
      ready = resolved.action_keys.include?(action_key)
      Entry.new(
        name: tool_class.name_value, description: tool_class.description_value.to_s,
        state: ready ? STATE_READY : STATE_NOT_GRANTED,
        tool: (Firefight.new(investigation, tool_class, action_key) if ready)
      )
    end
  end

  def self.connection_entries(investigation)
    principal = investigation.agent_principal
    resolved = granted(investigation)

    Integration::Tool.in_workspace(investigation.workspace).map do |tool|
      ready = tool.callable_by?(principal, resolved)
      Entry.new(
        name: tool.model_facing_name, description: tool.description.to_s,
        state: ready ? STATE_READY : STATE_NOT_GRANTED,
        tool: (Connection.new(investigation, tool) if ready)
      )
    end
  end

  # Named so the agent can say a provider is not wired up rather than that it found nothing.
  def self.unconnected_entries(investigation)
    connected = investigation.workspace.integrations.active.pluck(:provider)

    IntegrationProvider.all.reject { |provider| connected.include?(provider.key) }.map do |provider|
      Entry.new(name: provider.name, description: provider.description, state: STATE_NOT_CONNECTED, tool: nil)
    end
  end

  def self.granted(investigation)
    Ability::Resolver.resolve(investigation.agent_principal, investigation.workspace)
  end
end
