class Conversation::Tools::StartInvestigation < RubyLLM::Tool
  description "Start a full investigation when answering needs real work rather than a lookup. " \
              "It runs on its own and posts what it finds in this channel."

  def self.tool_name = "start_investigation"

  def initialize(conversation)
    super()
    @conversation = conversation
  end

  def execute
    incident = @conversation.incident
    return { error: "There is no incident here to investigate." } unless incident

    blocked = Investigation.unavailable_reason(@conversation.workspace) || incident.investigation_blocked_reason
    return { error: blocked } if blocked

    started = @conversation.start_investigation_as_asker do
      InvestigationService.new(@conversation.workspace).start(
        incident, trigger_source: Investigation::TRIGGER_CONVERSATION, triggered_by: @conversation.started_by
      )
    end
    return { error: "An investigation is already running for #{incident.identifier}." } unless started

    "Started. Tell the person it is running and that you will post what it finds here, then stop."
  rescue AbilityGateway::Denied
    { error: "#{asker_label} is not allowed to start an investigation." }
  end

  private

  def asker_label = @conversation.started_by.try(:display_name) || "Whoever asked"
end
