class IncidentCreationService
  def initialize(workspace)
    @workspace = workspace
  end

  def create_channel(incident)
    adapter = WorkspaceAdapter.for(@workspace)
    result = adapter.create_channel(name: incident.generated_channel_name, is_private: incident.is_private)
    incident.update!(channel_id: result[:channel_id], channel_name: result[:channel_name])
    result
  rescue AdapterError::ChannelExists
    fallback_name = "#{incident.generated_channel_name}-#{Time.current.to_i}"
    result = adapter.create_channel(name: fallback_name, is_private: incident.is_private)
    incident.update!(channel_id: result[:channel_id], channel_name: result[:channel_name])
    result
  end

  def set_channel_metadata(incident)
    adapter = WorkspaceAdapter.for(@workspace)
    topic = "Severity: #{incident.incident_severity.name} | Status: #{incident.incident_status.name}"
    purpose = "Incident response channel for #{incident.identifier}"
    adapter.set_channel_metadata(channel_id: incident.channel_id, topic: topic, purpose: purpose)
  end

  def post_quick_actions_message(incident)
    adapter = WorkspaceAdapter.for(@workspace)
    message_ts = incident.initial_message_ts

    unless message_ts
      result = adapter.post_incident_quick_actions(
        channel_id: incident.channel_id,
        incident: incident
      )
      message_ts = result[:message_ts]
      incident.update!(initial_message_ts: message_ts)
    end

    adapter.pin_message(channel_id: incident.channel_id, timestamp: message_ts)
    { message_ts: message_ts }
  end

  def post_announcement(incident)
    return { skipped: true } unless @workspace.incidents_channel_id

    if incident.is_private
      Rails.logger.info({ event: "incident.announcement_skipped", incident_id: incident.id, reason: "private_incident" })
      return { skipped: true }
    end

    return { message_ts: incident.announcement_message_ts } if incident.announcement_message_ts

    adapter = WorkspaceAdapter.for(@workspace)
    result = adapter.post_incident_announcement(
      channel_id: @workspace.incidents_channel_id,
      incident: incident
    )
    incident.update!(announcement_message_ts: result[:message_ts])
    { message_ts: result[:message_ts] }
  end

  def invite_declarer(incident)
    adapter = WorkspaceAdapter.for(@workspace)
    adapter.invite_user(channel_id: incident.channel_id, user_id: incident.declared_by.platform_user_id)
  end

  def create_incident_event(incident)
    incident.create_initial_update!(created_by: incident.declared_by)
    { ok: true }
  end
end
