# One integration tool. A refusal comes back as a result the agent works around, never an exception.
class Investigation::Tools::Connection < RubyLLM::Tool
  def initialize(investigation, tool)
    super()
    @investigation = investigation
    @tool = tool
  end

  def name = @tool.model_facing_name

  def description = @tool.description.to_s

  def parameters_schema = @tool.params_schema.presence || { "type" => "object", "properties" => {} }

  # The arguments match the tool's own schema, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    run(arguments.transform_keys(&:to_s))
  end

  private

  def run(arguments)
    Investigation::ToolCall.run!(@investigation, action_key: @tool.action_key, params: arguments) do
      integration = @tool.integration
      environment_row = integration.resolve_environment(nil)
      text_of(integration.executor.call(tool: @tool, environment_row: environment_row, arguments: arguments))
    end.value
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
