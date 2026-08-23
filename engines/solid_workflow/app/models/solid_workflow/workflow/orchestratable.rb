module SolidWorkflow
  class Workflow < Record
    module Orchestratable
      extend ActiveSupport::Concern

      def enqueue_next_steps
        reload
        all_steps = steps.reload.to_a

        Rails.logger.debug({
          event: "workflow.orchestration.start",
          workflow_id: id,
          workflow_state: state,
          steps_count: all_steps.count
        })

        return if completed? || paused?

        step_map = all_steps.index_by(&:name)
        ready = all_steps.select { |s| s.ready_to_run?(step_map) }
        ready = apply_concurrency_limit(all_steps, ready)

        ready.each do |step|
          step.populate_input_data(all_steps, step_map: step_map)
        end

        SolidWorkflow::Step.transaction do
          ready.each do |step|
            next unless step.changed?

            SolidWorkflow::Step.where(
              id: step.id,
              status: step.status_was,
              updated_at: step.updated_at_was
            ).update_all(
              input: step.input,
              updated_at: Time.current
            )
          end
        end

        ready.each do |step|
          SolidWorkflow::RunStepJob.set(queue: step.queue_name).perform_later(step.id)
        end

        if ready.any?
          Rails.logger.info({
            event:      "workflow.orchestration.enqueued",
            workflow_id: id,
            step_names: ready.map(&:name)
          })
        end

        update_workflow_state(all_steps)
      end

      def enqueue_next_steps_later
        SolidWorkflow::OrchestrateJob.perform_later(id)
      end

      private

      def apply_concurrency_limit(all_steps, ready_steps)
        max_concurrent = workflow_config.dig("max_concurrent_steps")
        return ready_steps unless max_concurrent

        running_count = all_steps.count(&:running?)
        available_slots = [ max_concurrent - running_count, 0 ].max

        ready_steps.take(available_slots)
      end

      def update_workflow_state(all_steps)
        reload

        if all_steps.all? { |s| s.succeeded? || s.skipped? }
          record_event(SolidWorkflow::Events::Workflow::SUCCEEDED) if transition!(:succeeded, from: %i[pending running])

        elsif all_steps.any?(&:failed?)
          if transition!(:failed, from: %i[pending running])
            SolidWorkflow::Step.where(workflow_id: id, status: :pending).update_all(
              status: :cancelled,
              completed_at: completed_at,
              updated_at: completed_at
            )

            record_event(SolidWorkflow::Events::Workflow::FAILED)
          end

        elsif pending?
          transition!(:running, from: :pending)
        end
      end
    end
  end
end
