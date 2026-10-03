# One rated answer replayed in a regression run, and whether the replay still got it right.
class Investigation::RegressionResult < ApplicationRecord
  self.table_name = "investigation_regression_results"

  STATUS_PENDING = "pending"
  STATUS_PASSED = "passed"
  STATUS_FAILED = "failed"
  # The replay could not finish, which says nothing about the answer either way.
  STATUS_ERRORED = "errored"
  # The workspace stopped letting Firefight test Halon before its case was replayed.
  STATUS_SKIPPED = "skipped"
  STATUSES = [ STATUS_PENDING, STATUS_PASSED, STATUS_FAILED, STATUS_ERRORED, STATUS_SKIPPED ].freeze
  EXPECTED = [ Investigation::Finding::OUTCOME_CONFIRMED, Investigation::Finding::OUTCOME_WRONG ].freeze
  # Longer than any replay is allowed to run, so a case still pending after it was started has lost its worker.
  STALE_AFTER = 2.hours

  belongs_to :regression_run, class_name: "Investigation::RegressionRun", inverse_of: :results
  belongs_to :finding, class_name: "Investigation::Finding"
  belongs_to :replay, class_name: "Investigation", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :expected, inclusion: { in: EXPECTED }

  scope :stale, -> { where(status: STATUS_PENDING).where(started_at: ...STALE_AFTER.ago) }

  # Starts the replay once, so a retried job never runs and pays for the same case twice.
  def claim!
    won = self.class.where(id: id, status: STATUS_PENDING, started_at: nil).update_all(started_at: Time.current, updated_at: Time.current)
    reload
    won == 1
  end

  # Settles a pending case once, so a retried job never overwrites what an earlier attempt decided.
  def settle!(status:, **columns)
    won = self.class.where(id: id, status: STATUS_PENDING).update_all(status: status, finished_at: Time.current, updated_at: Time.current, **columns)
    reload
    won == 1
  end
end
