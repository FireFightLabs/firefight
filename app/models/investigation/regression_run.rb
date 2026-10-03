# One pass over the regression cases on one version of Halon's prompt and one model, so a change that makes Halon
# worse at incidents it once got right, or makes it repeat a mistake, shows before customers see it.
class Investigation::RegressionRun < ApplicationRecord
  self.table_name = "investigation_regression_runs"

  TRIGGER_PROMPT_CHANGE = "prompt_change"
  TRIGGER_OPERATOR = "operator"
  TRIGGERS = [ TRIGGER_PROMPT_CHANGE, TRIGGER_OPERATOR ].freeze

  STATUS_RUNNING = "running"
  STATUS_FINISHED = "finished"
  STATUSES = [ STATUS_RUNNING, STATUS_FINISHED ].freeze

  # The latest rated answers, enough to catch a regression without a run costing more than a few dollars.
  CASES = 30

  belongs_to :started_by, class_name: "User", optional: true
  has_many :results, class_name: "Investigation::RegressionResult", dependent: :destroy, inverse_of: :regression_run

  validates :trigger, inclusion: { in: TRIGGERS }
  validates :status, inclusion: { in: STATUSES }
  validates :prompt_version, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def running? = status == STATUS_RUNNING

  # Finishes once no case is left pending, in one statement, so the last two cases ending together finish it once.
  def finish_if_done!
    pending = Investigation::RegressionResult.where(regression_run_id: id, status: Investigation::RegressionResult::STATUS_PENDING).select(:id)
    won = self.class.where(id: id, status: STATUS_RUNNING).where.not(Investigation::RegressionResult.where(id: pending).arel.exists)
                    .update_all(status: STATUS_FINISHED, finished_at: Time.current, updated_at: Time.current)
    reload
    won == 1
  end

  # The run before this one on the same model, for which cases changed between them.
  def previous
    self.class.where(model: model, provider: provider).where(created_at: ...created_at).recent.first
  end
end
