class IncidentUpdateReminderJob < ApplicationJob
  queue_as :default

  def perform(incident_id, expected_next_update_at)
    incident = Incident.find_by(id: incident_id)
    return unless incident
    return unless incident.active?
    return unless incident.next_update_at&.iso8601 == expected_next_update_at

    target_member = incident.lead || incident.declared_by
    return unless target_member&.platform_user_id

    incident.workspace.adapter.post_incident_update_reminder(
      channel_id: incident.channel_id,
      user_id: target_member.platform_user_id,
      incident: incident
    )
  end
end
