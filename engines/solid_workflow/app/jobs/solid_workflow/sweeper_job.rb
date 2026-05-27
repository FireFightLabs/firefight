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
        Rails.logger.warn({ event: "workflow.sweeper.resetting_orphan", step_id: step.id })

        step.update!(
          status: :pending,
          last_error: "Step was running but worker appears to have crashed (reset by sweeper)"
        )

        step.workflow.record_event(SolidWorkflow::Events::Step::RESET, step: step, reason: "sweeper")
      end
    end

    def sweep_timed_out_workflows
      SolidWorkflow::Workflow.timed_out.each do |workflow|
        Rails.logger.warn({
          event: "workflow.sweeper.timeout",
          workflow_id: workflow.id,
          workflow_class: workflow.workflow_class,
          timeout_seconds: workflow.workflow_config.dig("timeout"),
          running_duration: Time.current - (workflow.started_at || workflow.created_at)
        })

        workflow.transaction do
          workflow.steps.where(status: %i[pending running]).update_all(
            status: :cancelled,
            completed_at: Time.current
          )

          workflow.update!(
            state: :failed,
            completed_at: Time.current
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
