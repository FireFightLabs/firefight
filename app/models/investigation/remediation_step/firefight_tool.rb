# One of Firefight's own tools that a fix's step runs, such as invite_responders. It answers what a step asks of the tool
# it runs the way a connection's tool does: who may run it and the gateway action it is authorized as.
Investigation::RemediationStep::FirefightTool = Data.define(:tool_class, :action_key, :workspace) do
  def ability_action = Ability::Action.lookup(action_key, workspace)

  def callable_by?(member, resolved = nil, arguments: nil) = member.permitted_to?(ability_action, workspace, resolved: resolved)

  def read_only? = false

  def model_facing_name = tool_class.name_value.to_s
end
