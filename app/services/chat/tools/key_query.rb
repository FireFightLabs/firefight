# One of a resource's key checks (ResourceMap::KeyQueries), such as a service's p95 latency, run through the capability
# it names, so the call is authorized, approved, ledgered and replayed as the provider's own action, exactly as the
# capability tool would be. The answer starts with how the reading compares with the resource's normal.
class Chat::Tools::KeyQuery < RubyLLM::Tool
  NAME = ResourceMap::KeyQueries::TOOL_NAME

  # reads are [spec, tools that could answer, tools this agent may run] for each capability that only reads.
  def initialize(agent_run, reads)
    super()
    @agent_run = agent_run
    @reads = reads.to_h { |spec, able, callable| [ spec.key, [ spec, able, callable ] ] }
  end

  def name = NAME

  def description = ResourceMap::KeyQueries::DESCRIPTION

  # The same schema an outside agent is handed over MCP.
  def parameters_schema = ResourceMap::KeyQueries::SCHEMA

  def call(tool_call: nil, **arguments)
    given = arguments.transform_keys(&:to_s)
    resource = ResourceMap::Resource.locate(@agent_run.workspace, @agent_run.acting_principal, given["resource"])
    return refused(tool_call, resource) if resource.is_a?(String)

    check = ResourceMap::KeyQueries.find(resource.kind, given["query"])
    return refused(tool_call, ResourceMap::KeyQueries.unknown(resource, given["query"])) unless check

    spec, able, callable = @reads[check.capability]
    return refused(tool_call, "No connection you may use offers #{Integrations::Capabilities.spec(check.capability).what} for #{resource.scoped_name}.") unless spec

    plan = ResourceMap::KeyQueries.plan(resource, check, principal: @agent_run.acting_principal, tools: callable)
    return refused(tool_call, plan.refusal) unless plan.available?

    minutes = ResourceMap::KeyQueries.minutes(given["minutes"])
    capability = Chat::Tools::Capability.new(@agent_run, spec, able, callable: callable)
    text = capability.call(tool_call: tool_call, **plan.arguments(minutes).symbolize_keys)
    answered = capability.answered
    return text unless answered

    "#{ResourceMap::KeyQueries.headline(check, answered.call, plan.metric, answered.result)}\n\n#{text}"
  end

  private

  def refused(tool_call, text)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    text
  end
end
