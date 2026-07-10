class TimelineEventSerializer < BaseSerializer
  object_as :event

  type :string
  def id
    event.id
  end

  type :string
  def event_type
    event.event_type
  end

  type :string
  def actor
    event.actor&.actor_display_name || "System"
  end

  type :string
  def created_at
    event.created_at.utc.iso8601
  end

  type :string
  def description
    event.description
  end

  type "{ field: string; before: string; after: string }[]", optional: true
  def changes
    return nil unless event.eventable.is_a?(IncidentUpdate) && event.changed_fields.any?

    current = event.eventable
    previous = previous_incident_update(current)

    event.changed_fields.map do |field|
      {
        field: field,
        before: previous&.display_value_for(field).to_s,
        after: current.display_value_for(field).to_s
      }
    end
  end

  type :string, optional: true
  def details
    eventable = event.eventable
    return eventable.message if eventable.respond_to?(:message) && eventable.message.present?

    d = event.metadata["message"] || event.metadata[:message]
    d.is_a?(String) ? d : nil
  end

  type "{ name: string; mimeType: string | null; slackPermalink: string | null; downloadUrl: string | null; byteSize: number | null }", optional: true
  def file
    return nil unless event.event_type == IncidentEvent::MESSAGE_FILE_SHARED

    meta = event.metadata.with_indifferent_access
    {
      name: meta[:file_name].to_s,
      mimeType: meta[:mime_type].presence,
      slackPermalink: meta[:permalink].presence,
      downloadUrl: artifact_path(event),
      byteSize: meta[:byte_size]
    }
  end

  private

  def previous_incident_update(current)
    IncidentUpdate
      .where(incident_id: current.incident_id)
      .where("created_at < ?", current.created_at)
      .order(created_at: :desc)
      .first
  end

  def artifact_path(event)
    return nil unless event.artifact.attached?

    Rails.application.routes.url_helpers.rails_blob_path(event.artifact, only_path: true)
  end
end
