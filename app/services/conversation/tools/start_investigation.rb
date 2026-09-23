class Conversation::Tools::StartInvestigation < RubyLLM::Tool
  description "Start a full investigation when answering needs real work rather than a lookup. " \
              "It runs on its own and posts what it finds in this channel."

  def self.tool_name = Mcp::Tools::START_INVESTIGATION

  def initialize(turn)
    super()
    @turn = turn
  end

  # Takes nothing, so the base argument check is skipped the way the other wrappers skip it.
  def call(tool_call: nil, **)
    incident = @turn.incident
    return refused(tool_call, "There is no incident here to investigate.") unless incident

    blocked = Investigation.start_refusal(incident)
    return refused(tool_call, blocked) if blocked

    started = @turn.start_investigation do
      InvestigationService.new(@turn.workspace).start(
        incident, trigger_source: Investigation::TRIGGER_CONVERSATION, triggered_by: @turn.asker
      )
    end
    return refused(tool_call, Investigation.already_running_message(incident)) unless started

    "Started. Tell the person it is running and that you will post what it finds here, then stop."
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
