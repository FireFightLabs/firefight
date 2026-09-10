class WebhookDelivery < ApplicationRecord
  STALE_THRESHOLD = 7.days

  belongs_to :webhook
  belongs_to :incident_event

  # Decided once where the response is known, so no reader recomputes the
  # outcome from other columns.
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

  # A fresh row so the replay has its own audit trail, carrying the original
  # bytes so it sends what was sent before rather than re-rendering.
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
