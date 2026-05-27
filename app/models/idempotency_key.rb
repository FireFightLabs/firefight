class IdempotencyKey < ApplicationRecord
  EXPIRY = 24.hours

  belongs_to :workspace

  validates :key, presence: true
  validates :resource_type, presence: true
  validates :resource_id, presence: true

  scope :stale, -> { where(created_at: ...EXPIRY.ago) }

  def self.cleanup(batch_size: 500, pause: 0.1)
    BatchedDelete.run(
      stale,
      label: "idempotency_keys.cleanup",
      batch_size: batch_size,
      pause: pause,
      metadata: { expiry_hours: EXPIRY.to_i / 3_600 }
    )
  end
end
