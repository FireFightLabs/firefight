class WebhookDelivery < ApplicationRecord
  STALE_THRESHOLD = 7.days

  belongs_to :webhook
  belongs_to :incident_event

  enum :state, { pending: "pending", in_progress: "in_progress", completed: "completed", errored: "errored" }, default: :pending

  scope :ordered, -> { order(created_at: :desc, id: :desc) }
  scope :stale, -> { where(created_at: ...STALE_THRESHOLD.ago) }

  after_create_commit :deliver_later

  def self.cleanup(batch_size: 500, pause: 0.1)
    sleep pause until stale.limit(batch_size).delete_all.zero?
  end

  def succeeded?
    completed? && error_message.blank? && response_code&.between?(200, 299)
  end

  def failed?
    (errored? || completed?) && !succeeded?
  end

  private

  def deliver_later
    Webhooks::DeliveryJob.perform_later(self)
  end
end
