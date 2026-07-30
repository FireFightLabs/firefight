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

  type :string, optional: true
  def actor_avatar_url
    actor = event.actor
    return nil unless actor.respond_to?(:user)

    actor.user&.avatar_url
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
    blob = event.artifact.attached? ? event.artifact.blob : nil

    # The blob describes what downloadUrl actually returns, so it wins over the
    # Slack metadata. Events recorded before that metadata was captured carry
    # only a details key, and would otherwise render with no name or size.
    name = blob&.filename.to_s.presence || meta[:file_name].presence
    permalink = meta[:permalink].presence
    download = artifact_path(event)
    return nil if name.blank? && download.blank? && permalink.blank?

    {
      name: name.to_s,
      mimeType: blob&.content_type.presence || meta[:mime_type].presence,
      slackPermalink: permalink,
      downloadUrl: download,
      byteSize: blob&.byte_size || meta[:byte_size]
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
