class InvestigationStep < ApplicationRecord
  STATUS_PENDING = "pending"
  STATUS_RUNNING = "running"
  STATUS_SUCCEEDED = "succeeded"
  STATUS_FAILED = "failed"
  STATUSES = [ STATUS_PENDING, STATUS_RUNNING, STATUS_SUCCEEDED, STATUS_FAILED ].freeze

  belongs_to :investigation
  belongs_to :hypothesis, optional: true

  # Tool output is the customer's data, and a replay needs it in full.
  encrypts :raw_result
  encrypts :compacted_result

  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(:created_at, :id) }

  def succeed!(compacted_result:, raw_result: nil)
    update!(
      status: STATUS_SUCCEEDED, compacted_result: compacted_result, raw_result: raw_result,
      completed_at: Time.current
    )
  end

  # The reason goes in its own column, so it is readable in a query and no branch
  # reads it back as something a tool returned.
  def fail!(reason)
    reason = reason.class.name.demodulize unless reason.is_a?(String)
    update!(status: STATUS_FAILED, error_summary: reason, completed_at: Time.current)
  end
end
