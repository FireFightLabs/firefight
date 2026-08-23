class WebhookDelivery < ApplicationRecord
  STALE_THRESHOLD = 7.days

  belongs_to :webhook
  belongs_to :incident_event

  # Decided once, where the response is known. succeeded is a 2xx, failed is
  # any other response or a failure to send at all, and the two in between are
  # the queue. No reader has to recompute the outcome from other columns.
  enum :state, { pending: "pending", in_progress: "in_progress", succeeded: "succeeded", failed: "failed" }, default: :pending

  scope :ordered, -> { order(created_at: :desc, id: :desc) }
  scope :stale, -> { where(created_at: ...STALE_THRESHOLD.ago) }

  after_create_commit :deliver_later

  def self.cleanup(batch_size: 500, pause: 0.1)
    BatchedDelete.run(
      stale,
      label: "webhook_deliveries.cleanup",
      batch_size: batch_size,
      pause: pause,
      metadata: { stale_days: STALE_THRESHOLD.to_i / 86_400 }
    )
  end

  # Creates a fresh delivery against the same webhook + event so the replay has
  # its own audit row and attempt counter, carrying the original bytes so a
  # replay sends what was sent before rather than re-rendering an event that
  # may have drifted since. A row that never rendered one falls back to
  # rendering at delivery. The new row's after_create_commit enqueues
  # Webhooks::DeliveryJob.
  def replay!
    self.class.create!(
      webhook: webhook,
      incident_event: incident_event,
      event_type: event_type,
      signed_payload: signed_payload
    )
  end

  private

  def deliver_later
    Webhooks::DeliveryJob.perform_later(self)
  end
end
