# One of Firefight's own tools, shared with MCP so a tool never means two things.
class Chat::Tools::Firefight < RubyLLM::Tool
  def initialize(agent_run, tool_class, action)
    super()
    @agent_run = agent_run
    @tool_class = tool_class
    @action = action
  end

  # RubyLLM pauses the turn before a call that needs the person's decision.
  def requires_approval? = @agent_run.confirms?(@action)

  def name = @tool_class.name_value

  def description = @tool_class.description_value.to_s

  def parameters_schema = @tool_class.input_schema_value.to_h

  def call(tool_call: nil, **arguments)
    invoke(arguments.symbolize_keys, tool_call_id: tool_call&.id)
  end

  private

  # The action comes from the arguments, since an upsert is a create or an update depending on its target.
  def invoke(arguments, tool_call_id:)
    action_key = Ability::Action.system_key(*@tool_class.authorization(@agent_run.workspace, arguments))
    attempt(action_key, arguments, tool_call_id: tool_call_id)
  rescue *Mcp::ToolDispatcher::TOOL_ERRORS => error
    failed(tool_call_id, text_of(Mcp::ToolDispatcher.tool_error_response(error)))
  end

  # The words still go to the model. The mark is for whoever reads the chat afterwards.
  def failed(tool_call_id, text)
    Chat::Tools.mark_failed(@agent_run, tool_call_id)
    text
  end

  def attempt(action_key, arguments, tool_call_id:, approval_id: nil)
    # The block answers with the text, so a run's step keeps what the tool said rather than a response object.
    # An error response is still text the model reads, and the call is marked so a reader sees it failed.
    said = @agent_run.tool_call(
      action_key: action_key, params: arguments.transform_keys(&:to_s), tool_name: name,
      label: Chat::Tools.label(name, arguments), **{ approval_id: approval_id }.compact
    ) do
      response = Mcp::ToolDispatcher.run(
        tool: @tool_class, workspace: @agent_run.workspace, principal: @agent_run.acting_principal, args: arguments
      )
      Chat::Tools.mark_failed(@agent_run, tool_call_id) if response.error?
      text_of(response)
    end
    Chat::Tools.hand_over(@agent_run, name, said)
  rescue AbilityGateway::Denied
    failed(tool_call_id, @agent_run.refusal(action_key))
  rescue AbilityGateway::PendingApproval => pending
    if approval_id.nil? && approved_by_asker?(pending.approval)
      return attempt(action_key, arguments, tool_call_id: tool_call_id, approval_id: pending.approval.id)
    end

    Chat::Tools.waiting_for_approval(action_key)
  rescue *Mcp::ToolDispatcher::TOOL_ERRORS => error
    failed(tool_call_id, text_of(Mcp::ToolDispatcher.tool_error_response(error)))
  end

  def approved_by_asker?(approval) = requires_approval? && Chat::Tools.approve_for_asker(@agent_run, approval)

  def text_of(response)
    Array(response.content).filter_map { |part| part[:text] || part["text"] }.join("\n")
  end
end
