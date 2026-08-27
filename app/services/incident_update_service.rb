class IncidentUpdateService
  def initialize(workspace)
    @workspace = workspace
  end

  def update_quick_actions(incident)
    return unless incident.initial_message_ts

    @workspace.adapter.update_incident_quick_actions(
      channel_id: incident.channel_id,
      message_id: incident.initial_message_ts,
      incident: incident
    )
  end

  def update_announcement(incident)
    return unless incident.announcement_message_ts

    @workspace.adapter.update_incident_announcement(
      channel_id: @workspace.incidents_channel_id,
      message_id: incident.announcement_message_ts,
      incident: incident
    )
  end

  def update_channel_topic(incident)
    adapter = @workspace.adapter
    type_text = incident.incident_type ? " | Type: #{incident.incident_type.name}" : ""
    lead_text = incident.lead ? " | Lead: #{incident.lead.user.name}" : ""
    topic = "Severity: #{incident.incident_severity.name} | Status: #{incident.incident_status.name}#{type_text}#{lead_text}"
    adapter.set_channel_topic(
      channel_id: incident.channel_id,
      topic: topic
    )
  end

  def post_incident_update_message(incident, message:, updated_by_platform_user_id:, previous_status_name:, previous_severity_name:, previous_type_name: nil)
    @workspace.adapter.post_incident_update_message(
      channel_id: incident.channel_id,
      incident: incident,
      message: message,
      updated_by_platform_user_id: updated_by_platform_user_id,
      previous_status_name: previous_status_name,
      previous_severity_name: previous_severity_name,
      previous_type_name: previous_type_name
    )
  end

  def post_resolution_message(incident, resolved_by_platform_user_id:)
    @workspace.adapter.post_resolution_message(
      channel_id: incident.channel_id,
      incident: incident,
      resolved_by_platform_user_id: resolved_by_platform_user_id
    )
  end

  def post_resolution_announcement_thread(incident, resolved_by_platform_user_id:)
    return unless incident.announcement_message_ts

    @workspace.adapter.post_resolution_announcement_thread(
      channel_id: @workspace.incidents_channel_id,
      parent_message_id: incident.announcement_message_ts,
      incident: incident,
      resolved_by_platform_user_id: resolved_by_platform_user_id
    )
  end

  def post_reopen_message(incident, reopened_by_platform_user_id:, reason: nil)
    @workspace.adapter.post_reopen_message(
      channel_id: incident.channel_id,
      incident: incident,
      reopened_by_platform_user_id: reopened_by_platform_user_id,
      reason: reason
    )
  end

  def post_reopen_announcement_thread(incident, reopened_by_platform_user_id:, reason: nil)
    return unless incident.announcement_message_ts

    @workspace.adapter.post_reopen_announcement_thread(
      channel_id: @workspace.incidents_channel_id,
      parent_message_id: incident.announcement_message_ts,
      incident: incident,
      reopened_by_platform_user_id: reopened_by_platform_user_id,
      reason: reason
    )
  end

  # An escalation event holds who asked, who was asked and why, so each of
  # these reads it rather than being handed the same three values again.
  def post_escalation_message(incident, event:)
    @workspace.adapter.post_escalation_message(
      channel_id: incident.channel_id,
      incident: incident,
      escalated_by: event.actor,
      escalated_to: escalation_target(event),
      reason: event.metadata["reason"]
    )
  end

  def post_escalation_announcement_thread(incident, event:)
    return unless incident.announcement_message_ts

    @workspace.adapter.post_escalation_announcement_thread(
      channel_id: @workspace.incidents_channel_id,
      parent_message_id: incident.announcement_message_ts,
      incident: incident,
      escalated_by: event.actor,
      escalated_to: escalation_target(event),
      reason: event.metadata["reason"]
    )
  end

  def post_escalation_direct_message(incident, event:)
    @workspace.adapter.post_escalation_direct_message(
      user_id: escalation_target(event).platform_user_id,
      incident: incident,
      escalated_by: event.actor,
      escalation_event_id: event.id,
      reason: event.metadata["reason"]
    )
  end

  def post_escalation_acknowledged_message(incident, acknowledged_by_platform_user_id:, escalated_to_platform_user_id:)
    @workspace.adapter.post_escalation_acknowledged_message(
      channel_id: incident.channel_id,
      incident: incident,
      acknowledged_by_platform_user_id: acknowledged_by_platform_user_id,
      escalated_to_platform_user_id: escalated_to_platform_user_id
    )
  end

  def post_escalation_nudge_direct_message(incident, event:)
    @workspace.adapter.post_escalation_nudge_direct_message(
      user_id: escalation_target(event).platform_user_id,
      incident: incident,
      escalated_by: event.actor,
      escalation_event_id: event.id,
      reason: event.metadata["reason"]
    )
  end

  def post_incident_update_announcement_thread(incident, message:, updated_by_platform_user_id:, previous_status_name:, previous_severity_name:, previous_type_name: nil)
    return unless incident.announcement_message_ts

    @workspace.adapter.post_incident_update_announcement_thread(
      channel_id: @workspace.incidents_channel_id,
      parent_message_id: incident.announcement_message_ts,
      incident: incident,
      message: message,
      updated_by_platform_user_id: updated_by_platform_user_id,
      previous_status_name: previous_status_name,
      previous_severity_name: previous_severity_name,
      previous_type_name: previous_type_name
    )
  end

  private

  def escalation_target(event)
    Incident::EscalationTarget.from_metadata(@workspace, event.metadata)
  end
end
