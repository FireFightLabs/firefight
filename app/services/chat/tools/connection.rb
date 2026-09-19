# One integration tool. A refusal comes back as a result the agent works around, never an exception.
class Chat::Tools::Connection < RubyLLM::Tool
  def initialize(agent_run, tool)
    super()
    @agent_run = agent_run
    @tool = tool
  end

  def name = @tool.model_facing_name

  def description = @tool.description.to_s

  def parameters_schema = @tool.params_schema.presence || { "type" => "object", "properties" => {} }

  # The arguments match the tool's own schema, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    invoke(arguments.transform_keys(&:to_s))
  end

  private

  def invoke(arguments)
    @agent_run.tool_call(action_key: @tool.action_key, params: arguments) do
      integration = @tool.integration
      environment_row = integration.resolve_environment(nil)
      text_of(integration.executor.call(tool: @tool, environment_row: environment_row, arguments: arguments))
    end
  rescue Conversation::AskerDenied
    "Not allowed: the person you are answering cannot read #{@tool.action_key} in this workspace. Say so, and carry on with what you can reach."
  rescue AbilityGateway::Denied
    "Not allowed: this agent has no grant for #{@tool.action_key} in this workspace."
  rescue AbilityGateway::PendingApproval
    "Needs an approval and was not run: #{@tool.action_key}. Carry on with what you can reach and say what you could not check."
  rescue Integrations::Error => error
    "#{@tool.action_key} failed: #{error.message}"
  end

  def text_of(result)
    Array(result["content"]).filter_map { |part| part["text"] }.join("\n").presence || result.to_json
  end
end
