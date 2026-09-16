# What the agent may call during a run.
module Investigation::Tools
  def self.for(investigation)
    [ RecordHypothesis.new(investigation), Conclude.new(investigation), *connection_tools(investigation) ]
  end

  def self.connection_tools(investigation)
    principal = investigation.agent_principal
    resolved = Ability::Resolver.resolve(principal, investigation.workspace)

    Integration::Tool.in_workspace(investigation.workspace)
      .select { |tool| tool.callable_by?(principal, resolved) }
      .map { |tool| Connection.new(investigation, tool) }
  end
end
