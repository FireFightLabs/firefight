class EventRouter
  # Every event type is either subscribable (webhooks receive it) or named
  # internal here, so a new type is a deliberate decision, never a silent
  # drop. The test asserts the two lists cover EVENT_TYPES exactly.
  INTERNAL_ONLY = [
    IncidentEvent::MESSAGE_PINNED,
    IncidentEvent::MESSAGE_UNPINNED,
    IncidentEvent::MESSAGE_FILE_SHARED,
    IncidentEvent::ESCALATION_ACKNOWLEDGED,
    IncidentEvent::ESCALATION_NUDGED,
    IncidentEvent::ALERT_ATTACHED,
    IncidentEvent::ALERT_RESOLVED,
    # Retired: bulk-apply became step-by-step claiming (#286) and nothing
    # emits this any more. Listed so the coverage assertion stays exact; a
    # revival needs an emitter before it needs a subscription.
    IncidentEvent::RUNBOOK_APPLIED
  ].freeze

  def self.route(event)
    return if INTERNAL_ONLY.include?(event.event_type)

    unless Webhook::SUBSCRIBABLE_EVENTS.include?(event.event_type)
      Rails.logger.warn({ event: "event_router.unknown_event_type", event_type: event.event_type })
      return
    end

    [ Webhooks::EventSubscriber ].each do |subscriber|
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
