class EventRouter
  # Every event type is subscribable or listed here, and a test asserts the
  # two lists cover EVENT_TYPES exactly, so a new type is never a silent drop.
  INTERNAL_ONLY = [
    IncidentEvent::MESSAGE_PINNED,
    IncidentEvent::MESSAGE_UNPINNED,
    IncidentEvent::MESSAGE_FILE_SHARED,
    IncidentEvent::ESCALATION_ACKNOWLEDGED,
    IncidentEvent::ESCALATION_NUDGED,
    IncidentEvent::ALERT_ATTACHED,
    IncidentEvent::ALERT_RESOLVED,
    # Nothing emits this since bulk-apply became step-by-step claiming.
    # Listed so the coverage assertion stays exact.
    IncidentEvent::RUNBOOK_APPLIED
  ].freeze

  def self.route(event)
    return if INTERNAL_ONLY.include?(event.event_type)

    unless Webhook::SUBSCRIBABLE_EVENTS.include?(event.event_type)
      Rails.logger.warn({ event: "event_router.unknown_event_type", event_type: event.event_type })
      return
    end

    [ Webhooks::EventSubscriber, Onboarding::EventSubscriber ].each do |subscriber|
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
