# One of Firefight's own tools, the same ones an outside agent reaches over MCP. The definition is
# shared so a tool never means two things, and the gateway still authorizes each call as the agent.
class Chat::Tools::Firefight < RubyLLM::Tool
  def initialize(agent_run, tool_class, action_key)
    super()
    @agent_run = agent_run
    @tool_class = tool_class
    @action_key = action_key
  end

  def name = @tool_class.name_value

  def description = @tool_class.description_value.to_s

  def parameters_schema = @tool_class.input_schema_value.to_h

  def call(tool_call: nil, **arguments)
    invoke(arguments.symbolize_keys)
  end

  private

  def invoke(arguments)
    @agent_run.tool_call(action_key: @action_key, params: arguments.transform_keys(&:to_s)) do
      text_of(@tool_class.perform(workspace: @agent_run.workspace, args: arguments))
    end
  rescue Conversation::AskerDenied
    "Not allowed: the person you are answering cannot read #{@action_key} in this workspace. Say so, and carry on with what you can reach."
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
