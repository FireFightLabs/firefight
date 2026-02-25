class ProcessDomainEventJob < ApplicationJob
  queue_as :events

  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(event_hash)
    event = DomainEvent.from_h(event_hash)
    EventRouter.route(event)
  end
end
