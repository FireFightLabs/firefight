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
    return { error: "#{asker_label} is not allowed to start an investigation." } unless asker_may_start?

    started = InvestigationService.new(@conversation.workspace).start(
      incident, trigger_source: Investigation::TRIGGER_CONVERSATION, triggered_by: @conversation.started_by
    )
    return { error: "An investigation is already running for #{incident.identifier}." } unless started

    "Started. Tell the person it is running and that you will post what it finds here, then stop."
  end

  private

  # Starting a run spends money and posts in the channel, so the person asking needs the same
  # permission they would need to type the command.
  def asker_may_start?
    return false unless @conversation.started_by

    AbilityGateway.authorize!(
      principal: @conversation.started_by,
      action_key: Ability::Action.system_key(
        Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE
      ),
      workspace: @conversation.workspace,
      context: { source: AbilityGateway::SOURCE_CONVERSATION, incident_id: @conversation.incident_id }
    )
    true
  rescue AbilityGateway::Denied, AbilityGateway::PendingApproval
    false
  end

  def asker_label = @conversation.started_by.try(:display_name) || "Whoever asked"
end
