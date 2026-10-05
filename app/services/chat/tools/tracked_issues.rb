# An issue the agent opens while it works on an incident is kept on it as an action or a follow-up, and closing that issue
# completes it, so the incident and the tracker agree without the agent having to remember. Which tool opened or closed
# an issue is the integrations layer's to say (Integrations::Issues). Each write is incidents.update through the gateway,
# as the agent's own create_action_item and complete_action_item calls would be, and acts as whoever the run acts as.
module Chat::Tools::TrackedIssues
  UPDATE_ACTION_KEY = Ability::Action.system_key(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE)
  REFUSED = [ AbilityGateway::Denied, AbilityGateway::PendingApproval ].freeze

  # Offered beside the tool's own arguments and never sent to the provider.
  KIND_ARG = "keep_on_incident_as".freeze
  KIND_PARAMETER = {
    "type" => "string",
    "enum" => IncidentAction::ACTION_TYPES,
    "description" => "How Firefight keeps the new issue on the incident this chat is about. action is work to do while " \
                     "the incident is live, such as a fix or a mitigation. followup is work for after it, such as hardening " \
                     "or a cleanup. Left out, it is an action while the incident is live and a follow-up once it is over."
  }.freeze
  KIND_WORDS = { IncidentAction::ACTION_TYPE_ACTION => "an action", IncidentAction::ACTION_TYPE_FOLLOWUP => "a follow-up" }.freeze

  def self.with_kind(schema)
    schema = schema.deep_dup
    schema["properties"] = (schema["properties"] || {}).merge(KIND_ARG => KIND_PARAMETER)
    schema
  end

  # A sentence for the agent saying what was recorded, or nil when the call opened or closed nothing worth recording.
  def self.after(agent_run, tool:, environment_row:, scope:, arguments:, result:, kind: nil)
    report = Integrations::Issues.report(tool: tool, environment_row: environment_row, arguments: arguments, result: result) do |read_tool, read_arguments, &run|
      read(agent_run, read_tool, read_arguments, scope, &run)
    end
    return nil unless report

    report.opened? ? record(agent_run, report, kind) : complete(agent_run, report)
  rescue AdapterError => error
    "Firefight could not finish keeping #{report.key || 'the issue'} on the incident: #{error.message}"
  end

  def self.read(agent_run, read_tool, read_arguments, scope, &)
    agent_run.tool_call(
      action_key: read_tool.action_key, params: read_arguments, scope: scope, tool_name: read_tool.model_facing_name,
      label: Chat::Tools.label(read_tool.model_facing_name, read_arguments), &
    ).value
  rescue *REFUSED
    nil
  end

  # The kind asked for, unless the incident no longer takes actions, in which case the work can only come after it.
  def self.kind_for(incident, asked)
    live = incident.action_item_blocked_reason(IncidentAction::ACTION_TYPE_ACTION).nil?
    return IncidentAction::ACTION_TYPE_FOLLOWUP unless live

    IncidentAction::ACTION_TYPES.include?(asked) ? asked : IncidentAction::ACTION_TYPE_ACTION
  end

  def self.record(agent_run, report, asked)
    incident = agent_run.incident
    return nil if incident.nil? || incident.incident_actions.tracking(report.url).exists?

    named = report.key || "the issue"
    kind = kind_for(incident, asked)
    params = { "incident" => incident.identifier, "kind" => kind, "link" => report.url }
    agent_run.tool_call(action_key: UPDATE_ACTION_KEY, params: params, tool_name: Mcp::Tools::CREATE_ACTION_ITEM, label: "Recording #{named} as #{KIND_WORDS[kind]}") do
      IncidentActionService.new(agent_run.workspace).create_action(
        incident: incident, created_by: agent_run.acting_principal, action_type: kind,
        description: report.title || named, external_key: report.key, external_url: report.url
      )
    end
    said = "Firefight recorded #{named} on #{incident.identifier} as #{KIND_WORDS[kind]} with its link, so do not add it again."
    return said if asked.blank? || asked == kind

    "#{said} It is #{KIND_WORDS[kind]} rather than #{KIND_WORDS[asked] || asked}, since #{incident.identifier} is over."
  rescue *REFUSED
    "#{named} was not recorded on #{incident.identifier}, since this chat may not update the incident."
  end

  # Whichever incident the issue was recorded on, since it is often closed from a chat about something else.
  def self.complete(agent_run, report)
    open = IncidentAction.in_workspace(agent_run.workspace).tracking(report.url).where.not(status: IncidentAction::STATUS_DONE).includes(:incident).to_a
    named = report.key || "the issue"
    completed = open.filter_map do |action|
      params = { "incident" => action.incident.identifier, "action_item" => action.id }
      agent_run.tool_call(action_key: UPDATE_ACTION_KEY, params: params, tool_name: Mcp::Tools::COMPLETE_ACTION_ITEM, label: "Completing the item for #{named}") do
        IncidentActionService.new(agent_run.workspace).complete_action(action: action, completed_by: agent_run.acting_principal)
      end
      "#{KIND_WORDS[action.action_type].split.last} on #{action.incident.identifier}"
    rescue *REFUSED
      nil
    end
    return nil if completed.empty?

    "Firefight marked the #{completed.uniq.to_sentence} for #{named} done."
  end
  private_class_method :read, :kind_for, :record, :complete
end
