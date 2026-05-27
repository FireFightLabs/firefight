module SolidWorkflow
  module Events
    module Workflow
      STARTED = "workflow.started"
      RUNNING = "workflow.running"
      SUCCEEDED = "workflow.succeeded"
      FAILED = "workflow.failed"
      CANCELLED = "workflow.cancelled"
      PAUSED = "workflow.paused"
      RESUMED = "workflow.resumed"
    end

    module Step
      STARTED = "step.started"
      SUCCEEDED = "step.succeeded"
      ATTEMPT_FAILED = "step.attempt_failed"
      FAILED = "step.failed"
      SKIPPED = "step.skipped"
      CANCELLED = "step.cancelled"
      RETRY_SCHEDULED = "step.retry_scheduled"
      MANUAL_RETRY = "step.manual_retry"
      MANUAL_SKIP = "step.manual_skip"
      RESET = "step.reset"
    end
  end
end
