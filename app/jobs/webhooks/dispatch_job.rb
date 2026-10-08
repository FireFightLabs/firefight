class Webhooks::DispatchJob < ApplicationJob
  queue_as :webhooks

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(event_hash)
    event = DomainEvent.from_h(event_hash)
    incident = event.incident
    return if incident.is_test?

    workspace = incident.workspace

    # Run again after a stopped worker, or retried part way, it adds only the deliveries still missing.
    sent = WebhookDelivery.where(incident_event: event.incident_event, event_type: event.event_type).select(:webhook_id)
    workspace.webhooks.triggered_by(event.event_type).where.not(id: sent).find_each do |webhook|
      WebhookDelivery.create!(
        webhook: webhook,
        incident_event: event.incident_event,
        event_type: event.event_type
      )
    end
  end
end
