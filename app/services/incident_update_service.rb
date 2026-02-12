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
end
