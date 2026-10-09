module SolidWorkflow
  class SweeperJob < ActiveJob::Base
    queue_as { SolidWorkflow.queue_name }

    def perform
      sweep_stuck_workflows
      sweep_orphaned_steps
      sweep_timed_out_workflows
    end

    private

    def sweep_stuck_workflows
      SolidWorkflow::Workflow.stuck.find_each do |workflow|
        Rails.logger.info({ event: "workflow.sweeper.resuming", workflow_id: workflow.id })
        SolidWorkflow::OrchestrateJob.perform_later(workflow.id)
      end
    end

    def sweep_orphaned_steps
      SolidWorkflow::Step.orphaned.find_each do |step|
        if step.attempts >= step.max_attempts
          next unless move_orphan(step, status: :failed, completed_at: Time.current,
                                        last_error: "Step crashed the worker on every attempt (failed by sweeper after #{step.attempts} attempts)")

          Rails.logger.warn({ event: "workflow.sweeper.failing_orphan", step_id: step.id, attempts: step.attempts })
          step.workflow.record_event(SolidWorkflow::Events::Step::FAILED, step: step, reason: "sweeper_max_attempts")
          step.workflow.enqueue_next_steps_later
        else
          next unless move_orphan(step, status: :pending, last_error: "Step was running but worker appears to have crashed (reset by sweeper)")

          Rails.logger.warn({ event: "workflow.sweeper.resetting_orphan", step_id: step.id })
          step.workflow.record_event(SolidWorkflow::Events::Step::RESET, step: step, reason: "sweeper")
        end
      end
    end

    # Only a step still running as it was when the sweep read it, so one a resumed job took up since is left to that job.
    def move_orphan(step, **changes)
      moved = SolidWorkflow::Step.where(id: step.id, status: :running, updated_at: step.updated_at)
                                 .update_all(**changes, claimed_by: nil, updated_at: Time.current)
      step.reload if moved == 1
      moved == 1
    end

    def sweep_timed_out_workflows
      SolidWorkflow::Workflow.timed_out.find_each do |workflow|
        Rails.logger.warn({
          event: "workflow.sweeper.timeout",
          workflow_id: workflow.id,
          workflow_class: workflow.workflow_class,
          timeout_seconds: workflow.workflow_config.dig("timeout"),
          running_duration: Time.current - (workflow.started_at || workflow.created_at)
        })

        workflow.transaction do
          # Guarded so a workflow the orchestrator just finished is left alone.
          next unless workflow.transition!(:failed, from: %i[pending running])

          workflow.steps.where(status: %i[pending running]).update_all(
            status: :cancelled,
            completed_at: workflow.completed_at
          )

          workflow.record_event(
            SolidWorkflow::Events::Workflow::FAILED,
            reason: "timeout",
            timeout_seconds: workflow.workflow_config.dig("timeout")
          )
        end
      end
    end
  end
end
