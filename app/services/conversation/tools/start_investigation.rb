class Conversation::Tools::StartInvestigation < RubyLLM::Tool
  description "Start a full investigation when answering needs real work rather than a lookup. " \
              "It runs on its own and posts what it finds in this channel."

  def self.tool_name = "start_investigation"

  def initialize(turn)
    super()
    @turn = turn
  end

  def execute
    incident = @turn.incident
    return { error: "There is no incident here to investigate." } unless incident

    blocked = Investigation.unavailable_reason(@turn.workspace) || incident.investigation_blocked_reason
    return { error: blocked } if blocked

    started = @turn.start_investigation do
      InvestigationService.new(@turn.workspace).start(
        incident, trigger_source: Investigation::TRIGGER_CONVERSATION, triggered_by: @turn.asker
      )
    end
    return { error: "An investigation is already running for #{incident.identifier}." } unless started

    "Started. Tell the person it is running and that you will post what it finds here, then stop."
  rescue AbilityGateway::Denied, AbilityGateway::PendingApproval
    { error: "#{@turn.asker_name} is not allowed to start an investigation." }
  end
end
