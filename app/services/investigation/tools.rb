# What the agent may call during a run. The grants decide, not this list: every tool the agent's
# account holds, whether it reads Firefight's own records or a connected provider.
module Investigation::Tools
  def self.for(investigation)
    [ RecordHypothesis.new(investigation), Conclude.new(investigation),
      *firefight_tools(investigation), *connection_tools(investigation) ]
  end

  def self.firefight_tools(investigation)
    resolved = granted(investigation)

    Mcp::Tools.all.filter_map do |tool_class|
      resource, action = tool_class.authorization(investigation.workspace, {})
      action_key = Ability::Action.system_key(resource, action)
      next unless resolved.action_keys.include?(action_key)

      Firefight.new(investigation, tool_class, action_key)
    end
  end

  def self.connection_tools(investigation)
    principal = investigation.agent_principal
    resolved = granted(investigation)

    Integration::Tool.in_workspace(investigation.workspace)
      .select { |tool| tool.callable_by?(principal, resolved) }
      .map { |tool| Connection.new(investigation, tool) }
  end

  def self.granted(investigation)
    Ability::Resolver.resolve(investigation.agent_principal, investigation.workspace)
  end
end
