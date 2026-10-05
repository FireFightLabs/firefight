# An issue the agent opens while it works on an incident becomes one of the incident's follow-ups, and closing that issue
# completes it, so the incident and the tracker agree without the agent having to remember. Which tool opened or closed
# an issue is the integrations layer's to say (Integrations::Issues). Each write is incidents.update through the gateway,
# as the agent's own create_action_item and complete_action_item calls would be, and acts as whoever the run acts as.
module Chat::Tools::IssueFollowUps
  UPDATE_ACTION_KEY = Ability::Action.system_key(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE)
  REFUSED = [ AbilityGateway::Denied, AbilityGateway::PendingApproval ].freeze

  # A sentence for the agent saying what was recorded, or nil when the call opened or closed nothing worth recording.
  def self.after(agent_run, tool:, environment_row:, scope:, arguments:, result:)
    report = Integrations::Issues.report(tool: tool, environment_row: environment_row, arguments: arguments, result: result) do |read_tool, read_arguments, &run|
      read(agent_run, read_tool, read_arguments, scope, &run)
    end
    return nil unless report

    report.opened? ? record(agent_run, report) : complete(agent_run, report)
  rescue AdapterError => error
    "Firefight could not finish keeping #{report.key || 'the issue'} on the incident's follow-ups: #{error.message}"
  end

  def self.read(agent_run, read_tool, read_arguments, scope, &)
    agent_run.tool_call(
      action_key: read_tool.action_key, params: read_arguments, scope: scope, tool_name: read_tool.model_facing_name,
      label: Chat::Tools.label(read_tool.model_facing_name, read_arguments), &
    ).value
  rescue *REFUSED
    nil
  end

  def self.record(agent_run, report)
    incident = agent_run.incident
    return nil if incident.nil? || incident.incident_actions.tracking(report.url).exists?

    named = report.key || "the issue"
    params = { "incident" => incident.identifier, "kind" => IncidentAction::ACTION_TYPE_FOLLOWUP, "link" => report.url }
    agent_run.tool_call(action_key: UPDATE_ACTION_KEY, params: params, tool_name: Mcp::Tools::CREATE_ACTION_ITEM, label: "Recording #{named} as a follow-up") do
      IncidentActionService.new(agent_run.workspace).create_action(
        incident: incident, created_by: agent_run.acting_principal, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP,
        description: report.title || named, external_key: report.key, external_url: report.url
      )
    end
    "Firefight recorded #{named} on #{incident.identifier} as a follow-up with its link, so do not add it again."
  rescue *REFUSED
    "#{named} was not recorded on #{incident.identifier} as a follow-up, since this chat may not update the incident."
  end

  # Whichever incident the issue was recorded on, since it is often closed from a chat about something else.
  def self.complete(agent_run, report)
    open = IncidentAction.in_workspace(agent_run.workspace).tracking(report.url).where.not(status: IncidentAction::STATUS_DONE).includes(:incident).to_a
    completed = open.filter_map do |action|
      params = { "incident" => action.incident.identifier, "action_item" => action.id }
      agent_run.tool_call(action_key: UPDATE_ACTION_KEY, params: params, tool_name: Mcp::Tools::COMPLETE_ACTION_ITEM, label: "Completing the follow-up for #{report.key || 'the issue'}") do
        IncidentActionService.new(agent_run.workspace).complete_action(action: action, completed_by: agent_run.acting_principal)
      end
      action.incident.identifier
    rescue *REFUSED
      nil
    end
    return nil if completed.empty?

    "Firefight marked the follow-up for #{report.key || 'the issue'} done on #{completed.uniq.to_sentence}."
  end
  private_class_method :read, :record, :complete
end
