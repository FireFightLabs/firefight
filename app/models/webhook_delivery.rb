class WebhookDelivery < ApplicationRecord
  STALE_THRESHOLD = 7.days

  belongs_to :webhook
  belongs_to :incident_event

  enum :state, { pending: "pending", in_progress: "in_progress", completed: "completed", errored: "errored" }, default: :pending

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

  def succeeded?
    completed? && error_message.blank? && response_code&.between?(200, 299)
  end

  def failed?
    (errored? || completed?) && !succeeded?
  end

  # Creates a fresh delivery against the same webhook + event so the replay
  # has its own audit row, attempt counter, and signed_payload. The new row's
  # after_create_commit enqueues Webhooks::DeliveryJob.
  def replay!
    self.class.create!(
      webhook: webhook,
      incident_event: incident_event,
      event_type: event_type
    )
  end

  private

  def deliver_later
    Webhooks::DeliveryJob.perform_later(self)
  end
end
