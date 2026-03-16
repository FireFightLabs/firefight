class EscalationAcknowledgementReminderJob < ApplicationJob
  queue_as :events

  discard_on ActiveRecord::RecordNotFound

  def perform(incident_id, escalation_event_id, escalated_by_platform_user_id, escalated_to_platform_user_id, reason = nil)
    incident = Incident.find(incident_id)
    escalation_event = incident.incident_events.find(escalation_event_id)

    return if escalation_event.details&.dig("acknowledged_by_platform_user_id").present?
    return if EscalationAcknowledgementTracker.acknowledged?(workspace_id: incident.workspace_id, escalation_event_id: escalation_event.id)

    service = IncidentUpdateService.new(incident.workspace)
    service.post_escalation_nudge_direct_message(
      incident,
      escalated_by_platform_user_id: escalated_by_platform_user_id,
      escalated_to_platform_user_id: escalated_to_platform_user_id,
      escalation_event_id: escalation_event.id,
      reason: reason
    )
  end
end
