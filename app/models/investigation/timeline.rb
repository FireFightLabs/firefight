# A run on an incident is part of the incident's story, so its start and its end are on the incident's timeline.
module Investigation::Timeline
  extend ActiveSupport::Concern

  # A resumed run starts again, and the timeline says so once.
  # A run tied to an incident after it finished is placed on the timeline when it happened, before the incident.
  def note_started!
    note!(IncidentEvent::INVESTIGATION_STARTED, at: created_at, message: brief&.dig(Investigation::Brief::KEY_SYMPTOM))
  end

  # The short answer goes with the full one, so a reader of the timeline gets what a channel reads first.
  def note_answered!(finding)
    note!(IncidentEvent::INVESTIGATION_ANSWERED, at: finding.created_at || Time.current, message: finding.summary,
                                                 **Investigation::Timeline.short_answer(finding))
  end

  def self.short_answer(finding)
    { headline: finding.headline, sureness: finding.sureness, what_is_wrong: finding.what_is_wrong_line.presence,
      suggested_fix: finding.suggested_fix_line.presence }.compact
  end

  def note_stopped!(reason)
    note!(IncidentEvent::INVESTIGATION_STOPPED, reason: reason)
  end

  private

  def note!(event_type, at: Time.current, **details)
    return unless incident
    return if incident.incident_events.where(event_type: event_type).exists?([ "metadata->>'investigation_id' = ?", id ])

    incident.incident_events.create!(
      event_type: event_type, actor: acting_principal, created_at: at, metadata: { investigation_id: id, **details }.compact
    )
  end
end
