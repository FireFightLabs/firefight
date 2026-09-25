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

  # The same schema an outside MCP client is handed, so a connection wired per environment is reachable from a chat.
  def parameters_schema = @tool.offered_schema

  # The arguments match the tool's own schema, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    invoke(arguments.transform_keys(&:to_s), tool_call_id: tool_call&.id)
  end

  private

  def invoke(given, tool_call_id:, approval_id: nil)
    environment_entry = @tool.integration.environment_entry_for(given[Integration::Tool::ENVIRONMENT_ARG])
    arguments = given.except(Integration::Tool::ENVIRONMENT_ARG)
    scope = environment_entry ? { "environment" => environment_entry.id } : {}

    result = nil
    said = @agent_run.tool_call(
      action_key: @tool.action_key, params: arguments, scope: scope, tool_name: name,
      label: Chat::Tools.label(name, arguments), **{ approval_id: approval_id }.compact
    ) do
      integration = @tool.integration
      environment_row = integration.resolve_environment(environment_entry&.id)
      result = integration.executor.call(tool: @tool, environment_row: environment_row, arguments: arguments, box_key: @agent_run.code_box_key)
      text_of(result)
    end
    keep_charts(tool_call_id, result, said.step)
    Chat::Tools.hand_over(@agent_run, name, said)
  rescue Integration::UnknownEnvironment => error
    failed(tool_call_id, error.message)
  rescue AbilityGateway::Denied
    failed(tool_call_id, @agent_run.refusal(@tool.action_key) + Mcp::ConnectionToolFactory.environment_hint(@tool))
  rescue AbilityGateway::PendingApproval => pending
    if approval_id.nil? && approved_by_asker?(pending.approval)
      return invoke(given, tool_call_id: tool_call_id, approval_id: pending.approval.id)
    end

    Chat::Tools.waiting_for_approval(@tool.action_key)
  rescue Integrations::Error => error
    # The provider's own words, so they are framed like anything else it said.
    failed(tool_call_id, FirefightAi::Evidence.frame(name, "#{@tool.action_key} failed: #{error.message}"))
  end

  # The words still go to the model. The mark is for whoever reads the chat afterwards.
  def failed(tool_call_id, text)
    Chat::Tools.mark_failed(@agent_run, tool_call_id)
    text
  end

  def approved_by_asker?(approval) = requires_approval? && Chat::Tools.approve_for_asker(@agent_run, approval)

  # A chart is for the person, so it is kept with the chat and never handed to the model.
  def keep_charts(tool_call_id, result, step_position)
    charts = result&.dig(Integrations::Telemetry::STRUCTURED, Integrations::Telemetry::CHARTS)
    return if charts.blank? || tool_call_id.blank?

    chat = @agent_run.chat
    Chat::Chart.record!(chat, tool_call_id, charts, step_position: step_position) if chat
  end

  def text_of(result)
    Array(result["content"]).filter_map { |part| part["text"] }.join("\n").presence || result.to_json
  end
end
