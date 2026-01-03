# WorkflowSweeperJob - Safety net and recovery mechanism for workflows
#
# This job runs periodically (typically every 5 minutes) to detect and fix
# workflow issues that can occur in production environments.
#
# It handles two critical failure scenarios:
# 1. Stuck Workflows - Workflows that stopped progressing due to infrastructure issues
# 2. Orphaned Steps - Steps stuck in "running" status due to worker crashes
#
# Scheduling (via Solid Queue):
#   production:
#     recurring:
#       workflow_sweeper:
#         class: WorkflowSweeperJob
#         schedule: "*/5 * * * *"  # Every 5 minutes
#
# See: docs/WorkflowSweeperJob.md for detailed explanation
#
class Workflows::WorkflowSweeperJob < ApplicationJob
  queue_as :workflows

  # Main entry point - runs both recovery mechanisms
  #
  # This job is safe to run frequently because:
  # - Uses advisory locks (won't double-execute)
  # - Only processes truly stuck workflows/steps
  # - Idempotent operations (safe to retry)
  #
  def perform
    sweep_stuck_workflows
    sweep_orphaned_steps
    sweep_timed_out_workflows
  end

  private

  # Detects and resumes workflows that have stopped progressing
  #
  # Problem Solved:
  #   Workflows can get "stuck" when the orchestrator fails to run due to:
  #   - Server crash during orchestration
  #   - Database transaction rollback
  #   - Job queue issues
  #   - Race conditions
  #
  # How It Works:
  #   1. Finds workflows in pending/running state
  #   2. That haven't updated in 5+ minutes (abnormally stale)
  #   3. Re-triggers orchestration via enqueue_next_steps
  #   4. Orchestrator uses advisory locks, so safe to call multiple times
  #
  # Example Scenario:
  #   - Step A completes successfully
  #   - RunStepJob calls workflow.enqueue_next_steps_later
  #   - Server crashes before OrchestrateJob runs
  #   - Workflow stuck: Step A done, Step B never starts
  #   - Sweeper detects and resumes workflow
  #
  # Timeframe: 5 minutes is reasonable since orchestration is quick
  #
  def sweep_stuck_workflows
    Workflow.stuck.find_each do |workflow|
      Rails.logger.info({ event: "workflow.sweeper.resuming", workflow_id: workflow.id })
      workflow.enqueue_next_steps
    end
  end

  # Detects and resets steps that were abandoned mid-execution
  #
  # Problem Solved:
  #   Steps can become "orphaned" when:
  #   - Worker process crashes while executing a step
  #   - Server dies during step execution
  #   - Container is killed (e.g., Kubernetes pod eviction)
  #   - Out of memory error kills the worker
  #
  # How It Works:
  #   1. Finds steps with status "running"
  #   2. That haven't updated in 10+ minutes (likely crashed)
  #   3. Resets step to "pending" status (does NOT increment attempts)
  #   4. Adds explanatory error message for debugging
  #   5. Records RESET event for audit trail
  #   6. Next orchestrator run will retry the step
  #
  # Example Scenario:
  #   - Step starts executing, status → "running"
  #   - Worker performs API call to external service
  #   - Worker crashes (server dies, OOM, etc.)
  #   - Step stuck in "running" status forever
  #   - Sweeper detects after 10 minutes and resets to pending
  #
  # Timeframe: 10 minutes allows steps to complete legitimate long-running work
  #
  # Safety:
  #   - Step methods should be idempotent (per best practices)
  #   - Retry logic still applies (max_attempts respected)
  #   - Won't create infinite loops
  #
  def sweep_orphaned_steps
    WorkflowStep.orphaned.find_each do |step|
      Rails.logger.warn({ event: "workflow.sweeper.resetting_orphan", step_id: step.id })

      step.update!(
        status: :pending,
        last_error: "Step was running but worker appears to have crashed (reset by sweeper)"
      )

      step.workflow.record_event(WorkflowEvents::Step::RESET, step: step, reason: "sweeper")
    end
  end

  # Detects and fails workflows that have exceeded their configured timeout
  #
  # Problem Solved:
  #   Workflows can run indefinitely if they don't have automatic cleanup,
  #   consuming resources and preventing proper incident resolution.
  #
  # How It Works:
  #   1. Finds workflows with a configured timeout
  #   2. Checks if running_duration > configured timeout
  #   3. Marks workflow as failed with timeout reason
  #   4. Cancels all pending/running steps
  #   5. Records TIMEOUT event for audit trail
  #
  # Example Scenario:
  #   - Workflow has timeout: 1.hour in workflow_config
  #   - Workflow started at 10:00 AM
  #   - Current time: 11:05 AM (65 minutes)
  #   - Sweeper marks it as failed due to timeout
  #
  # Timeframe: Checks every 5 minutes (sweeper frequency)
  #
  def sweep_timed_out_workflows
    Workflow.timed_out.each do |workflow|
      Rails.logger.warn({
        event: "workflow.sweeper.timeout",
        workflow_id: workflow.id,
        workflow_class: workflow.workflow_class,
        timeout_seconds: workflow.workflow_config.dig("timeout"),
        running_duration: Time.current - (workflow.started_at || workflow.created_at)
      })

      workflow.transaction do
        # Cancel all pending/running steps
        workflow.workflow_steps.where(status: %i[pending running]).update_all(
          status: :cancelled,
          completed_at: Time.current
        )

        # Mark workflow as failed
        workflow.update!(
          state: :failed,
          completed_at: Time.current
        )

        # Record timeout event
        workflow.record_event(
          WorkflowEvents::Workflow::FAILED,
          reason: "timeout",
          timeout_seconds: workflow.workflow_config.dig("timeout")
        )
      end
    end
  end
end
