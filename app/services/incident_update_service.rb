class IncidentUpdateService
  def initialize(workspace)
    @workspace = workspace
  end

  def update_quick_actions(incident)
    return unless incident.initial_message_ts

    adapter = WorkspaceAdapter.for(@workspace)
    adapter.update_incident_quick_actions(
      channel_id: incident.channel_id,
      ts: incident.initial_message_ts,
      incident: incident
    )
  end

  def update_announcement(incident)
    return unless incident.announcement_message_ts

    adapter = WorkspaceAdapter.for(@workspace)
    adapter.update_incident_announcement(
      channel_id: @workspace.incidents_channel_id,
      ts: incident.announcement_message_ts,
      incident: incident
    )
  end

  def update_channel_topic(incident)
    adapter = WorkspaceAdapter.for(@workspace)
    lead_text = incident.lead ? " | Lead: #{incident.lead.user.name}" : ""
    topic = "Severity: #{incident.incident_severity.name} | Status: #{incident.incident_status.name}#{lead_text}"
    adapter.set_channel_metadata(
      channel_id: incident.channel_id,
      topic: topic,
      purpose: "Incident response channel for #{incident.identifier}"
    )
  end

  def post_incident_update_message(incident, message:, updated_by_platform_user_id:, previous_status_name:, previous_severity_name:)
    adapter = WorkspaceAdapter.for(@workspace)
    adapter.post_incident_update_message(
      channel_id: incident.channel_id,
      incident: incident,
      message: message,
      updated_by_platform_user_id: updated_by_platform_user_id,
      previous_status_name: previous_status_name,
      previous_severity_name: previous_severity_name
    )
  end

  def post_incident_update_announcement_thread(incident, message:, updated_by_platform_user_id:, previous_status_name:, previous_severity_name:)
    return unless incident.announcement_message_ts

    adapter = WorkspaceAdapter.for(@workspace)
    adapter.post_incident_update_announcement_thread(
      channel_id: @workspace.incidents_channel_id,
      thread_ts: incident.announcement_message_ts,
      incident: incident,
      message: message,
      updated_by_platform_user_id: updated_by_platform_user_id,
      previous_status_name: previous_status_name,
      previous_severity_name: previous_severity_name
    )
  end
end
