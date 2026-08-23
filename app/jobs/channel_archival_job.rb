class ChannelArchivalJob < ApplicationJob
  queue_as :default

  # expected_resolved_at guards against archiving after a reopen-and-resolve
  # cycle. A canceled incident has no resolved_at to compare, so it passes nil
  # and leans on the terminal? and channel_archived_at guards instead.
  def perform(incident_id, expected_resolved_at = nil)
    incident = Incident.find_by(id: incident_id)
    return unless incident
    return unless incident.terminal?
    return if expected_resolved_at.present? && incident.resolved_at&.iso8601 != expected_resolved_at
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
  rescue AdapterError::AuthRevoked
    # Notifier was already fired inside the adapter. Re-raise so SolidQueue
    # surfaces the failure instead of silently swallowing a broken integration.
    raise
  rescue AdapterError => e
    Rails.logger.error({
      event: "channel_archival.failed",
      incident_id: incident_id,
      error_class: e.class.name,
      error: e.message
    })
  end
end
