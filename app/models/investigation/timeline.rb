# A run on an incident is part of the incident's story, so its start and its end are on the incident's timeline.
module Investigation::Timeline
  extend ActiveSupport::Concern

  # A resumed run starts again, and the timeline says so once.
  def note_started!
    note!(IncidentEvent::INVESTIGATION_STARTED, message: brief&.dig(Investigation::Brief::KEY_SYMPTOM))
  end

  def note_answered!(finding)
    note!(IncidentEvent::INVESTIGATION_ANSWERED, message: finding.summary)
  end

  def note_stopped!(reason)
    note!(IncidentEvent::INVESTIGATION_STOPPED, reason: reason)
  end

  private

  def note!(event_type, **details)
    return unless incident
    return if incident.incident_events.where(event_type: event_type).exists?([ "metadata->>'investigation_id' = ?", id ])

    incident.incident_events.create!(
      event_type: event_type, actor: acting_principal, metadata: { investigation_id: id, **details }.compact
    )
  end
end
