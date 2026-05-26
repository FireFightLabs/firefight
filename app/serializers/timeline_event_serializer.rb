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
    event.user&.user&.name || "System"
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
        before: previous&.public_send(field).to_s,
        after: current.public_send(field).to_s
      }
    end
  end

  type :string, optional: true
  def details
    d = event.metadata["message"] || event.metadata[:message]
    d.is_a?(String) ? d : nil
  end

  private

  def previous_incident_update(current)
    IncidentUpdate
      .where(incident_id: current.incident_id)
      .where("created_at < ?", current.created_at)
      .order(created_at: :desc)
      .first
  end
end
