class EscalationAcknowledgementReminderJob < ApplicationJob
  queue_as :events

  discard_on ActiveRecord::RecordNotFound

  def perform(incident_id, escalation_event_id)
    incident = Incident.find(incident_id)
    escalation_event = incident.incident_events.find(escalation_event_id)

    return if escalation_event.escalation_acknowledged?

    IncidentUpdateService.new(incident.workspace).post_escalation_nudge_direct_message(
      incident, event: escalation_event
    )

    record_nudged_event(incident, escalation_event)
  end

  private

  def record_nudged_event(incident, escalation_event)
    return if incident.incident_events
      .where(event_type: IncidentEvent::ESCALATION_NUDGED)
      .where("metadata @> ?", { escalation_event_id: escalation_event.id }.to_json)
      .exists?

    target = escalation_event.metadata.slice(
      "escalated_to_platform_user_id", "escalated_to_member_id", "escalated_to_name", "escalated_to_avatar_url"
    )
    incident.incident_events.create!(
      event_type: IncidentEvent::ESCALATION_NUDGED,
      metadata: target.merge(escalation_event_id: escalation_event.id)
    )
  end
end
