class Webhooks::DeliveryJob < ApplicationJob
  queue_as :webhooks

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def self.interrupted_too_often(webhook_delivery) = WebhookDelivery.give_up_interrupted!(WebhookDelivery.where(id: webhook_delivery.id))

  def perform(webhook_delivery)
    Webhooks::DeliveryService.deliver(webhook_delivery)
  end
end
