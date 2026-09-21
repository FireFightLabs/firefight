# One integration tool. A refusal comes back as a result the agent works around, never an exception.
class Chat::Tools::Connection < RubyLLM::Tool
  def initialize(agent_run, tool)
    super()
    @agent_run = agent_run
    @tool = tool
  end

  # RubyLLM pauses the turn before a call that needs the person's decision.
  def requires_approval? = @agent_run.confirms?(@tool.ability_action)

  def name = @tool.model_facing_name

  # Another system's words, so only text reaches the model and a runaway description is capped.
  def description = Chat::Tools.clean(@tool.description, Chat::Tools::FULL_DESCRIPTION)

  def parameters_schema = @tool.params_schema.presence || { "type" => "object", "properties" => {} }

  # The arguments match the tool's own schema, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    invoke(arguments.transform_keys(&:to_s))
  end

  private

  def invoke(arguments, approval_id: nil)
    said = @agent_run.tool_call(
      action_key: @tool.action_key, params: arguments, tool_name: name,
      label: Chat::Tools.label(name, arguments), **{ approval_id: approval_id }.compact
    ) do
      integration = @tool.integration
      environment_row = integration.resolve_environment(nil)
      text_of(integration.executor.call(tool: @tool, environment_row: environment_row, arguments: arguments))
    end
    Chat::Tools.hand_over(@agent_run, name, said)
  rescue AbilityGateway::Denied
    @agent_run.refusal(@tool.action_key)
  rescue AbilityGateway::PendingApproval => pending
    return invoke(arguments, approval_id: pending.approval.id) if approval_id.nil? && approved_by_asker?(pending.approval)

    Chat::Tools.waiting_for_approval(@tool.action_key)
  rescue Integrations::Error => error
    # The provider's own words, so they are framed like anything else it said.
    FirefightAi::Evidence.frame(name, "#{@tool.action_key} failed: #{error.message}")
  end

  def approved_by_asker?(approval) = requires_approval? && Chat::Tools.approve_for_asker(@agent_run, approval)

  def text_of(result)
    Array(result["content"]).filter_map { |part| part["text"] }.join("\n").presence || result.to_json
  end
end
