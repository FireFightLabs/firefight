class ChannelArchivalJob < ApplicationJob
  queue_as :default

  def perform(incident_id, expected_resolved_at)
    incident = Incident.find_by(id: incident_id)
    return unless incident
    return unless incident.closed?
    return unless incident.resolved_at&.iso8601 == expected_resolved_at
    return unless incident.workspace.archive_channel_enabled
    return unless incident.channel_id.present?
    return if incident.channel_archived_at.present?

    incident.workspace.adapter.archive_channel(channel_id: incident.channel_id)
    incident.update!(channel_archived_at: Time.current, channel_archived_by: "system")

    Rails.logger.info({
      event: "channel_archival.archived",
      incident_id: incident.id,
      channel_id: incident.channel_id
    })
  rescue AdapterError::AlreadyArchived
    incident.update!(channel_archived_at: Time.current, channel_archived_by: "system")
  rescue AdapterError => e
    Rails.logger.error({
      event: "channel_archival.failed",
      incident_id: incident_id,
      error: e.message
    })
  end
end
