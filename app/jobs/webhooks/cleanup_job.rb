class Webhooks::CleanupJob < ApplicationJob
  queue_as :webhooks

  def perform
    WebhookDelivery.cleanup
  end
end
