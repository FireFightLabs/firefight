# How a run's record follows the engine. Each step row is written whole each time the step moves, keyed by the step's
# stable id and its iteration. The run's own status follows the engine and never leaves a finished state, except a
# failed run an operator took up again.
module Workflow::Run::Progress
  extend ActiveSupport::Concern

  # A failed run can be taken up again, a step retried or skipped from the operator console.
  REVIVABLE = Workflow::Run::OPEN + [ Workflow::Run::STATUS_FAILED ]
  ERROR_LIMIT = 2_000

  # A run whose details were dropped is left as its one line.
  def record_step!(step_key:, iteration:, **attributes)
    return if details_pruned?

    row = attributes.merge(run_id: id, step_key: step_key, iteration: iteration)
    row[:error] = self.class.redacted(row[:error].to_s.lines.first.to_s.strip).truncate(ERROR_LIMIT).presence
    Workflow::Run::Step.upsert_all([ row ], unique_by: %i[run_id step_key iteration], update_only: (attributes.keys + [ :error ]).uniq)
    signal_workflow_page
  end

  # Moves the run to what the engine says, with a started step making a queued run running.
  def record_status!(status, step_started: false, outputs: nil, error: nil)
    return if details_pruned?

    status = Workflow::Run::STATUS_RUNNING if status == Workflow::Run::STATUS_QUEUED && step_started
    return if status == self.status

    columns = {}
    columns[:started_at] = Time.current if status == Workflow::Run::STATUS_RUNNING && started_at.nil?
    if Workflow::Run::FINISHED.include?(status)
      columns[:finished_at] = Time.current
      columns[:outputs] = outputs if status == Workflow::Run::STATUS_SUCCEEDED
      columns[:error] = self.class.redacted(error.to_s).truncate(ERROR_LIMIT).presence if status == Workflow::Run::STATUS_FAILED
    else
      columns[:finished_at] = nil
    end
    move!(to: status, from: REVIVABLE - [ status ], **columns)
  end
end
