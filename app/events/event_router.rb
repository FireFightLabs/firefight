class EventRouter
  WEBHOOK_SUBSCRIBER = [ Webhooks::EventSubscriber ].freeze

  SUBSCRIBERS = {
    IncidentEvent::INCIDENT_CREATED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::INCIDENT_UPDATED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::INCIDENT_ACCEPTED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::LEAD_ASSIGNED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::ROLE_ASSIGNED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::ROLE_UNASSIGNED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::ACTION_CREATED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::ACTION_PICKED_UP => WEBHOOK_SUBSCRIBER,
    IncidentEvent::ACTION_COMPLETED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::INCIDENT_ESCALATED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::INCIDENT_RESOLVED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::INCIDENT_REOPENED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::INCIDENT_CANCELED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::POSTMORTEM_GENERATED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::POSTMORTEM_EDITED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::RELATIONSHIP_CREATED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::MARKED_DUPLICATE => WEBHOOK_SUBSCRIBER,
    IncidentEvent::MERGED_INTO => WEBHOOK_SUBSCRIBER,
    IncidentEvent::MESSAGE_PINNED => [],
    IncidentEvent::MESSAGE_UNPINNED => [],
    IncidentEvent::MESSAGE_FILE_SHARED => [],
    IncidentEvent::ESCALATION_ACKNOWLEDGED => [],
    IncidentEvent::ESCALATION_NUDGED => [],
    IncidentEvent::ALERT_ATTACHED => [],
    IncidentEvent::ALERT_RESOLVED => [],
    IncidentEvent::RUNBOOK_ATTACHED => WEBHOOK_SUBSCRIBER,
    IncidentEvent::RUNBOOK_APPLIED => WEBHOOK_SUBSCRIBER
  }.freeze

  def self.route(event)
    subscribers = SUBSCRIBERS[event.event_type]

    unless subscribers
      Rails.logger.warn({ event: "event_router.unknown_event_type", event_type: event.event_type })
      return
    end

    subscribers.each do |subscriber|
      subscriber.handle(event)
    rescue => e
      Rails.logger.error({
        event: "event_router.subscriber_failed",
        subscriber: subscriber.name,
        event_type: event.event_type,
        incident_id: event.incident_id,
        error: e.message
      })
      raise
    end
  end
end
