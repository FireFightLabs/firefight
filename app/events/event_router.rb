class EventRouter
  SUBSCRIBERS = {
    IncidentEvent::INCIDENT_CREATED => [],
    IncidentEvent::INCIDENT_UPDATED => [],
    IncidentEvent::LEAD_ASSIGNED => [],
    IncidentEvent::ACTION_CREATED => [],
    IncidentEvent::ACTION_PICKED_UP => [],
    IncidentEvent::ACTION_COMPLETED => [],
    IncidentEvent::INCIDENT_ESCALATED => [],
    IncidentEvent::INCIDENT_RESOLVED => [],
    IncidentEvent::INCIDENT_REOPENED => [],
    IncidentEvent::POSTMORTEM_GENERATED => [],
    IncidentEvent::RELATIONSHIP_CREATED => [],
    IncidentEvent::MARKED_DUPLICATE => [],
    IncidentEvent::MERGED_INTO => []
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
