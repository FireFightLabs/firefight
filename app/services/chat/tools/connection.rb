# One integration tool. A refusal comes back as a result the agent works around, never an exception.
class Chat::Tools::Connection < RubyLLM::Tool
  def initialize(agent_run, tool)
    super()
    @agent_run = agent_run
    @tool = tool
  end

  # RubyLLM pauses the turn before a call that needs the person's decision.
  def requires_approval? = @agent_run.confirms?(@tool.ability_action, tool_name: name)

  # A call whose words name another connection is refused rather than put to the person (Chat::Tools::Target).
  def approval_resolver = Chat::Tools::Target.resolver(@agent_run) { |given| misdirection(given).present? }

  def name = @tool.model_facing_name

  # Another system's words, so only text reaches the model and a runaway description is capped.
  def description
    said = Chat::Tools.clean(@tool.description, Chat::Tools::FULL_DESCRIPTION)
    reading_schema ? "#{said} #{guard::DESCRIPTION}" : said
  end

  # The same schema an outside MCP client is handed, so a connection wired per environment is reachable from a chat.
  # A call that waits for the person also asks for its intent, which the confirmation leads with.
  # A tool that can open an issue in a chat or run about an incident also asks how the issue is kept on it.
  def parameters_schema
    schema = reading_schema || @tool.offered_schema
    schema = Chat::Tools::TrackedIssues.with_kind(schema) if tracks_issues?
    requires_approval? ? Chat::Tools.with_intent(schema) : schema
  end

  # The arguments match the tool's own schema, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    given = arguments.transform_keys(&:to_s)
    return failed(tool_call&.id, gone) unless Integration::Tool.in_workspace(@agent_run.workspace).exists?(id: @tool.id)

    refused = misdirection(given) || Chat::Tools::Target.drift(@agent_run, tool_call&.id, Chat::Tools::Target.connection_label(@tool, given))
    return failed(tool_call&.id, refused) if refused

    @issue_kind = given[Chat::Tools::TrackedIssues::KIND_ARG]
    invoke(given.except(Chat::Tools::INTENT_ARG, Chat::Tools::TrackedIssues::KIND_ARG), tool_call_id: tool_call&.id)
  end

  private

  # Switched off, or its connection was, since the agent was handed it.
  def gone
    "#{name} was switched off since you were given it, so it was not run. An admin can switch it on in Integrations. " \
      "Tell the person, and open the tools again once they say it is on."
  end

  def misdirection(given)
    Chat::Tools::Target.misdirection(@tool.integration, Chat::Tools.intent_of(given), called: name) do |other|
      Chat::Tools::Target.reach_instead(other, @tool.name)
    end
  end

  def tracks_issues? = @agent_run.incident.present? && Integrations::Issues.opens?(@tool)

  def invoke(given, tool_call_id:)
    environment_entry = @tool.integration.environment_entry_for(given[Integration::Tool::ENVIRONMENT_ARG])
    run(reading(given.except(Integration::Tool::ENVIRONMENT_ARG)), environment_entry: environment_entry, tool_call_id: tool_call_id)
  rescue Integration::UnknownEnvironment, Integrations::ReadGuards::Refused => error
    failed(tool_call_id, error.message)
  end

  public

  # Whether the last run was refused or the provider failed it.
  def failed? = @failed == true

  # Whether the last run is waiting for someone to approve it.
  def waiting? = @waiting == true

  # What the provider answered on the last run, read into the capability's shapes, or nil when it did not answer.
  attr_reader :last_result

  # Runs the tool with arguments that are already its own, as this tool's action, through the gateway. A capability
  # call runs through here too, so it is authorized, approved, ledgered and replayed exactly like the tool itself.
  # shown_as is the name the agent called, present reads the provider's answer back into the capability's shapes.
  # alone is false when this is one of several answers to one call, so a failure here leaves the card to the caller.
  def run(arguments, environment_entry:, tool_call_id:, shown_as: name, present: nil, approval_id: nil, alone: true)
    @alone = alone
    @failed = false
    @waiting = false
    @last_result = nil
    scope = environment_entry ? { "environment" => environment_entry.id } : {}
    result = nil
    environment_row = nil
    said = @agent_run.tool_call(
      action_key: @tool.action_key, params: arguments, scope: scope, tool_name: shown_as,
      label: Chat::Tools.label(shown_as, arguments, workspace: @agent_run.workspace), **{ approval_id: approval_id }.compact
    ) do |authorization|
      integration = @tool.integration
      environment_row = integration.resolve_environment(environment_entry&.id)
      result = integration.executor.call(tool: @tool, environment_row: environment_row, arguments: arguments, box_key: @agent_run.code_box_key)
      result = present.call(result) if present
      @last_result = result
      next text_of(result) unless result["isError"] == true

      provider_failed!(tool_call_id, authorization, text_of(result))
      FirefightAi::Evidence.pointed(text_of(result))
    end
    keep_charts(tool_call_id, result, said.step)
    tracked = present.nil? && Chat::Tools::TrackedIssues.after(
      @agent_run, tool: @tool, environment_row: environment_row, scope: scope, arguments: arguments, result: result, kind: @issue_kind
    )
    reminder = Chat::Tools::SkillReminder.for(@agent_run, source: @tool.integration.provider, handle: @tool.name, tool_call_id: tool_call_id)
    [ Chat::Tools.hand_over(@agent_run, shown_as, said), tracked.presence, reminder ].compact.join("\n\n")
  rescue AbilityGateway::Denied
    failed(tool_call_id, @agent_run.refusal(@tool.action_key) + Mcp::ConnectionToolFactory.environment_hint(@tool))
  rescue AbilityGateway::PendingApproval => pending
    if approval_id.nil? && approved_by_asker?(pending.approval)
      return run(arguments, environment_entry: environment_entry, tool_call_id: tool_call_id, shown_as: shown_as, present: present,
                            approval_id: pending.approval.id, alone: alone)
    end

    @waiting = true
    Chat::Tools.waiting_for_approval(@tool.action_key)
  rescue Integrations::Error => error
    # The provider's own words, so they are framed like anything else it said.
    failed(tool_call_id, FirefightAi::Evidence.frame(shown_as, "#{@tool.action_key} failed: #{error.message}"))
  end

  private

  # The words still go to the model. The mark is for whoever reads the chat afterwards.
  def failed(tool_call_id, text)
    @failed = true
    Chat::Tools.mark_failed(@agent_run, tool_call_id) unless @alone == false
    text
  end

  # A provider that answers its own failure, as a remote server does, still failed the call, and a capability's reading
  # of the answer keeps an error an error. Its words still reach the model, so only the ledger is marked here, and the
  # card too unless this is one of several answers to one call.
  def provider_failed!(tool_call_id, authorization, said)
    @failed = true
    authorization.answer_failed!(said)
    Chat::Tools.mark_failed(@agent_run, tool_call_id) unless @alone == false
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

  # A run that only reads calls a tool that can write only once the call is shown to read, as its guard rewrites it.
  def reading(arguments)
    return arguments unless guarded?
    raise Integrations::ReadGuards::Refused, "#{name} can change things, so it is not used while investigating." unless guard

    guard.reading(@tool.name, arguments)
  end

  def guarded? = @agent_run.reads_only? && !@tool.read_only?

  def guard = @guard ||= Integrations::ReadGuards.for(@tool)

  # What the guard takes instead of the tool's own arguments, when it rewrites them, keeping the environment choice.
  def reading_schema
    schema = guarded? && guard&.schema
    return unless schema

    environment = @tool.offered_schema.dig("properties", Integration::Tool::ENVIRONMENT_ARG)
    environment ? schema.deep_merge("properties" => { Integration::Tool::ENVIRONMENT_ARG => environment }) : schema
  end
end
