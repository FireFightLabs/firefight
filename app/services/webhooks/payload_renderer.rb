class Webhooks::PayloadRenderer
  TEMPLATE_MAP = {
    IncidentEvent::INCIDENT_CREATED => "webhooks/events/incident_created",
    IncidentEvent::INCIDENT_UPDATED => "webhooks/events/incident_updated",
    IncidentEvent::INCIDENT_ACCEPTED => "webhooks/events/incident_updated",
    IncidentEvent::INCIDENT_RESOLVED => "webhooks/events/incident_resolved",
    IncidentEvent::INCIDENT_REOPENED => "webhooks/events/incident_reopened",
    IncidentEvent::INCIDENT_ESCALATED => "webhooks/events/incident_escalated",
    IncidentEvent::LEAD_ASSIGNED => "webhooks/events/lead_assigned",
    IncidentEvent::ROLE_ASSIGNED => "webhooks/events/role_assigned",
    IncidentEvent::ROLE_UNASSIGNED => "webhooks/events/role_assigned",
    IncidentEvent::ACTION_CREATED => "webhooks/events/action_created",
    IncidentEvent::ACTION_PICKED_UP => "webhooks/events/action_picked_up",
    IncidentEvent::ACTION_COMPLETED => "webhooks/events/action_completed",
    IncidentEvent::RUNBOOK_ATTACHED => "webhooks/events/runbook_attached",
    IncidentEvent::RUNBOOK_APPLIED => "webhooks/events/runbook_applied",
    IncidentEvent::POSTMORTEM_GENERATED => "webhooks/events/postmortem_generated",
    IncidentEvent::POSTMORTEM_EDITED => "webhooks/events/postmortem_edited",
    IncidentEvent::RELATIONSHIP_CREATED => "webhooks/events/relationship_created",
    IncidentEvent::MARKED_DUPLICATE => "webhooks/events/marked_duplicate",
    IncidentEvent::MERGED_INTO => "webhooks/events/merged_into"
  }.freeze

  def self.render(incident_event, delivery_id:)
    template = TEMPLATE_MAP.fetch(incident_event.event_type, "webhooks/events/generic")

    renderer.render(
      template: template,
      formats: :json,
      layout: false,
      assigns: {
        event: incident_event,
        delivery_id: delivery_id
      }
    ).strip
  end

  def self.template_for(event_type)
    TEMPLATE_MAP.fetch(event_type, "webhooks/events/generic")
  end

  def self.renderer
    @renderer ||= ApplicationController.renderer.new(https: !Rails.env.local?)
  end
end
