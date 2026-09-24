class Conversation::Tools::StartInvestigation < RubyLLM::Tool
  description "Start a full investigation when answering needs real work rather than a lookup. It needs no incident. " \
              "It runs on its own, for minutes, and posts what it finds here. Hand over what the person told you: what " \
              "is failing, roughly when it started, any names and any error text. Ask once when it started if nobody " \
              "has said, and accept not knowing as an answer."

  def self.tool_name = Mcp::Tools::START_INVESTIGATION

  def initialize(turn)
    super()
    @turn = turn
  end

  def parameters_schema
    { "type" => "object", "properties" => Investigation::Brief::SCHEMA.deep_stringify_keys, "required" => [] }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  # In a chat about an incident it investigates the incident. Anywhere else it investigates what the person said is
  # wrong, and the answer comes back to this chat.
  def call(tool_call: nil, **arguments)
    incident = @turn.incident
    brief = Investigation::Brief.from(arguments, source: Investigation::Brief::SOURCE_CHAT)
    blocked = Investigation.start_refusal(@turn.workspace, incident)
    return refused(tool_call, blocked) if blocked
    return refused(tool_call, "Say what is failing in the symptom, in the person's words.") if incident.nil? && brief.empty?

    started = @turn.start_investigation do
      InvestigationService.new(@turn.workspace).start(
        incident, trigger_source: Investigation::TRIGGER_CONVERSATION, triggered_by: @turn.asker, brief: brief,
        conversation: @turn.conversation, tool_call_id: tool_call&.id
      )
    end
    return refused(tool_call, Investigation.already_running_message(incident)) unless started

    "Started. Tell the person it is running and that its answer will come back here, then stop."
  rescue AbilityGateway::Denied, AbilityGateway::PendingApproval
    refused(tool_call, "#{@turn.asker_name} is not allowed to start an investigation.")
  end

  private

  # The words still go to the model. The mark is for whoever reads the chat afterwards.
  def refused(tool_call, text)
    Chat::Tools.mark_failed(@turn, tool_call&.id)
    { error: text }
  end
end
