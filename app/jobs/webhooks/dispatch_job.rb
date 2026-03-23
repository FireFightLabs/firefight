class Webhooks::DispatchJob < ApplicationJob
  queue_as :webhooks

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(event_hash)
    event = DomainEvent.from_h(event_hash)
    incident = event.incident
    workspace = incident.workspace

    workspace.webhooks.triggered_by(event.event_type).find_each do |webhook|
      WebhookDelivery.create!(
        webhook: webhook,
        incident_event: event.incident_event,
        event_type: event.event_type
      )
    end
  end
end
