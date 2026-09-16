# One of Firefight's own tools, the same ones an outside agent reaches over MCP. The definition is
# shared so a tool never means two things, and the gateway still authorizes each call as the agent.
class Investigation::Tools::Firefight < RubyLLM::Tool
  def initialize(investigation, tool_class, action_key)
    super()
    @investigation = investigation
    @tool_class = tool_class
    @action_key = action_key
  end

  def name = @tool_class.name_value

  def description = @tool_class.description_value.to_s

  def parameters_schema = @tool_class.input_schema_value.to_h

  def call(tool_call: nil, **arguments)
    run(arguments.symbolize_keys)
  end

  private

  def run(arguments)
    Investigation::ToolCall.run!(
      @investigation, action_key: @action_key, params: arguments.transform_keys(&:to_s)
    ) do
      text_of(@tool_class.perform(workspace: @investigation.workspace, args: arguments))
    end.value
  rescue AbilityGateway::Denied
    "Not allowed: this agent has no grant for #{@action_key} in this workspace."
  rescue AbilityGateway::PendingApproval
    "Needs an approval and was not run: #{@action_key}. Carry on with what you can reach and say what you could not check."
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => error
    "#{name} failed: #{error.message}"
  end

  def text_of(response)
    Array(response.content).filter_map { |part| part[:text] || part["text"] }.join("\n")
  end
end
