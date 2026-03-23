class Webhooks::DeliveryJob < ApplicationJob
  queue_as :webhooks

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(webhook_delivery)
    Webhooks::DeliveryService.deliver(webhook_delivery)
  end
end
