# new_log_patterns: a resource's recent logs read through the logs capability, so the call is authorized, approved,
# ledgered and replayed as the provider's own action, then mined into patterns and set against the patterns it usually
# prints (ResourceMap::LogTemplate). The agent reads the patterns, never the raw lines.
class Chat::Tools::LogPatterns < RubyLLM::Tool
  NAME = Integrations::Capabilities::LOG_PATTERNS_TOOL

  # logs is [spec, tools that could answer, tools this agent may run] for the logs capability.
  def initialize(agent_run, logs)
    super()
    @agent_run = agent_run
    @spec, @able, @callable = logs
  end

  def name = NAME

  def description = ResourceMap::LogTemplate::DESCRIPTION

  # The same schema an outside agent is handed over MCP.
  def parameters_schema = ResourceMap::LogTemplate::SCHEMA

  def call(tool_call: nil, **arguments)
    given = arguments.transform_keys(&:to_s)
    resource = ResourceMap::Resource.locate(@agent_run.workspace, @agent_run.acting_principal, given["resource"])
    if resource.is_a?(String)
      Chat::Tools.mark_failed(@agent_run, tool_call&.id)
      return resource
    end

    minutes = ResourceMap::KeyQueries.minutes(given["minutes"])
    capability = Chat::Tools::Capability.new(@agent_run, @spec, @able, callable: @callable)
    said = capability.call(tool_call: tool_call, resource: resource.id, minutes: minutes, limit: ResourceMap::LogTemplate::LINES)
    answered = capability.answered
    return said unless answered

    comparison = ResourceMap::LogTemplate.compare(resource, ResourceMap::LogMiner.lines_of(answered.result))
    ResourceMap::LogTemplate.report(resource, comparison, from: answered.call.environment_row.integration.display_name, minutes: minutes)
  end
end
