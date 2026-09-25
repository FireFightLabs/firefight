# One workflow run in full, with its steps placed for drawing and every event it recorded.
class OperatorWorkflowSerializer < OperatorWorkflowRowSerializer
  object_as :workflow

  STEP_STATUS_UNION = WorkflowRuns::STEP_STATUSES.map(&:inspect).join(" | ")
  STEP_TYPE = "{ id: string; name: string; status: #{STEP_STATUS_UNION}; attempts: number; maxAttempts: number | null; " \
              "lastError: string | null; skipReason: string | null; seconds: number | null; dependsOn: string[]; " \
              "column: number; row: number }[]".freeze

  type :string, optional: true
  def pause_reason = workflow.pause_reason

  type :string, optional: true
  def cancellation_reason = workflow.cancellation_reason

  type STEP_TYPE
  def steps
    Operator::WorkflowGraph.new(workflow.steps).nodes.map do |node|
      step = node.step
      {
        id: step.id, name: step.name, status: step.status, attempts: step.attempts.to_i, maxAttempts: step.max_attempts,
        lastError: step.last_error, skipReason: step.skip_reason,
        seconds: step.started_at && step.completed_at ? (step.completed_at - step.started_at).round(1) : nil,
        dependsOn: Array(step.depends_on), column: node.column, row: node.row
      }
    end
  end

  type "{ id: string; at: string; eventType: string; stepName: string | null; note: string | null; failed: boolean }[]"
  def events
    workflow.events.sort_by(&:created_at).map do |event|
      meta = event.metadata.to_h
      note = [ meta["reason"], meta["error"], meta["by"], ("attempt #{meta['attempt']}" if meta["attempt"]) ].compact_blank.join(" · ")
      {
        id: event.id, at: event.created_at.utc.iso8601, eventType: event.event_type, stepName: event.step&.name,
        note: note.presence, failed: WorkflowRuns::FAILURE_EVENTS.include?(event.event_type)
      }
    end
  end
end
