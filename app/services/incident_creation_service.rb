class IncidentCreationService
  def initialize(workspace)
    @workspace = workspace
  end

  def create_channel(incident)
    return if incident.channel_id.present?

    adapter = @workspace.adapter
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
    adapter = @workspace.adapter
    topic = "Severity: #{incident.incident_severity.name} | Status: #{incident.incident_status.name}"
    purpose = "Incident response channel for #{incident.identifier}"
    adapter.set_channel_metadata(channel_id: incident.channel_id, topic: topic, purpose: purpose)
  end

  def post_quick_actions_message(incident)
    adapter = @workspace.adapter
    message_ts = incident.initial_message_ts

    unless message_ts
      result = adapter.post_incident_quick_actions(
        channel_id: incident.channel_id,
        incident: incident
      )
      message_ts = result[:message_id]
      incident.update!(initial_message_ts: message_ts)
    end

    adapter.pin_message(channel_id: incident.channel_id, message_id: message_ts)
    { message_ts: message_ts }
  end

  def post_announcement(incident)
    return { skipped: true } unless @workspace.incidents_channel_id

    if incident.is_private
      Rails.logger.info({ event: "incident.announcement_skipped", incident_id: incident.id, reason: "private_incident" })
      return { skipped: true }
    end

    return { message_ts: incident.announcement_message_ts } if incident.announcement_message_ts

    result = @workspace.adapter.post_incident_announcement(
      channel_id: @workspace.incidents_channel_id,
      incident: incident
    )
    incident.update!(announcement_message_ts: result[:message_id])
    { message_ts: result[:message_id] }
  end

  # An agent has no account on the platform, so there is nobody to put in the
  # room. It still declared the incident, and the timeline says so.
  def invite_declarer(incident)
    platform_user_id = incident.declared_by&.platform_user_id
    return { skipped: true } if platform_user_id.blank?

    @workspace.adapter.invite_user(channel_id: incident.channel_id, user_id: platform_user_id)
  rescue AdapterError::AlreadyInChannel
    { invited_user: platform_user_id, already_in_channel: true }
  end

  # Alert-routed incidents: put the resolved responders in the room. They are
  # invited, not assigned. Leadership is taken via the existing quick action,
  # never imposed on someone who has not acknowledged.
  def invite_members(incident, membership_ids)
    return { skipped: true } if membership_ids.blank?

    user_ids = @workspace.workspace_memberships.where(id: membership_ids).pluck(:platform_user_id)
    return { skipped: true } if user_ids.empty?

    @workspace.adapter.invite_users(channel_id: incident.channel_id, user_ids: user_ids)
    { invited_users: user_ids }
  rescue AdapterError::AlreadyInChannel
    { invited_users: user_ids, already_in_channel: true }
  end

  def create_incident_event(incident)
    return { ok: true } if incident.incident_events.exists?(event_type: IncidentEvent::INCIDENT_CREATED)

    incident.record_change!(IncidentEvent::INCIDENT_CREATED, by: incident.declared_by)
    { ok: true }
  end
end
