class IncidentFileArchivalService
  def self.archive!(incident_event:, slack_file:)
    workspace = incident_event.incident.workspace
    archive_metadata = workspace.adapter.archive_slack_file(incident_event: incident_event, slack_file: slack_file)
    return unless archive_metadata[:archived]

    metadata = incident_event.metadata.deep_stringify_keys
    details = metadata["details"] || {}
    incident_event.update!(
      metadata: {
        **metadata,
        "details" => {
          **details,
          "object_key" => archive_metadata[:object_key],
          "blob_id" => archive_metadata[:blob_id],
          "byte_size" => archive_metadata[:byte_size],
          "checksum" => archive_metadata[:checksum]
        }
      }
    )
  rescue AdapterError => e
    Rails.logger.warn({ event: "incident_file_archival.failed", incident_event_id: incident_event.id, error: e.message })
  end
end
