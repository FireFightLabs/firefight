# One of Firefight's own tools, shared with MCP so a tool never means two things.
class Chat::Tools::Firefight < RubyLLM::Tool
  def initialize(agent_run, tool_class)
    super()
    @agent_run = agent_run
    @tool_class = tool_class
  end

  def name = @tool_class.name_value

  def description = @tool_class.description_value.to_s

  def parameters_schema = @tool_class.input_schema_value.to_h

  def call(tool_call: nil, **arguments)
    invoke(arguments.symbolize_keys)
  end

  private

  # The action comes from the arguments, since an upsert is a create or an update depending on its target.
  def invoke(arguments)
    action_key = Ability::Action.system_key(*@tool_class.authorization(@agent_run.workspace, arguments))
    response = @agent_run.tool_call(action_key: action_key, params: arguments.transform_keys(&:to_s)) do
      Mcp::ToolDispatcher.run(
        tool: @tool_class, workspace: @agent_run.workspace, principal: @agent_run.acting_principal, args: arguments
      )
    end
    text_of(response)
  rescue AbilityGateway::Denied
    @agent_run.refusal(action_key)
  rescue AbilityGateway::PendingApproval
    "Needs an approval and was not run: #{action_key}. Carry on with what you can reach and say what you could not check."
  rescue *Mcp::ToolDispatcher::TOOL_ERRORS => error
    text_of(Mcp::ToolDispatcher.tool_error_response(error))
  end

  def text_of(response)
    Array(response.content).filter_map { |part| part[:text] || part["text"] }.join("\n")
  end
end
