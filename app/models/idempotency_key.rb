class IdempotencyKey < ApplicationRecord
  EXPIRY = 24.hours

  belongs_to :workspace

  validates :key, presence: true, uniqueness: { scope: :workspace_id }
  validates :resource_type, presence: true
  validates :resource_id, presence: true

  scope :stale, -> { where(created_at: ...EXPIRY.ago) }

  def self.cleanup(batch_size: 500, pause: 0.1)
    sleep pause until stale.limit(batch_size).delete_all.zero?
  end
end
