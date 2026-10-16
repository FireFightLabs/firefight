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
        return unless runnable?

        step_map = all_steps.index_by(&:name)
        bypass_unreachable!(all_steps, step_map)
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

        # Read again, since the steps it enqueued may already have moved on.
        update_workflow_state(steps.reload.to_a)
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

      # A step on a route nobody took is bypassed, and so is whatever only it leads to, until nothing more moves. A
      # failure that stops the run leaves the rest to be cancelled instead.
      def bypass_unreachable!(all_steps, step_map)
        return if all_steps.any? { |step| step.failed? && !step.failure_tolerated? }

        loop do
          unreachable = all_steps.select { |step| step.pending? && step.graph? && step.unreachable?(step_map) }
          moved = unreachable.select do |step|
            SolidWorkflow::Step.where(id: step.id, status: :pending).update_all(status: :bypassed, completed_at: Time.current, updated_at: Time.current) == 1
          end
          break if moved.empty?

          moved.each do |step|
            step.status = "bypassed"
            record_event(SolidWorkflow::Events::Step::BYPASSED, step: step)
          end
        end
      end

      def update_workflow_state(all_steps)
        reload

        if all_steps.all? { |step| step.succeeded? || step.skipped? || step.bypassed? || step.failure_tolerated? }
          if transition!(:succeeded, from: %i[pending running waiting], result: workflow_klass.result_of(self))
            record_event(SolidWorkflow::Events::Workflow::SUCCEEDED)
          end

        elsif all_steps.any? { |step| step.failed? && !step.failure_tolerated? }
          if transition!(:failed, from: %i[pending running waiting])
            SolidWorkflow::Step.where(workflow_id: id, status: %i[pending waiting]).update_all(
              status: :cancelled,
              completed_at: completed_at,
              updated_at: completed_at
            )

            record_event(SolidWorkflow::Events::Workflow::FAILED)
            cancel_children!(reason: "workflow_failed", by: nil)
          end

        elsif parked?(all_steps)
          record_event(SolidWorkflow::Events::Workflow::WAITING) if transition!(:waiting, from: %i[pending running])

        elsif pending? || waiting?
          was_waiting = waiting?
          moved = transition!(:running, from: %i[pending waiting])
          record_event(SolidWorkflow::Events::Workflow::RUNNING, reason: "woken") if moved && was_waiting
        end
      end

      # Nothing runs or is about to, and something waits for a time, a signal or a child. A step pending only because
      # what it follows has not finished waits with it, and one pending for a retry does not.
      def parked?(all_steps)
        open = all_steps.reject(&:completed?)
        return false if open.none?(&:waiting?) || open.any?(&:running?)

        step_map = all_steps.index_by(&:name)
        open.select(&:pending?).all? { |step| step.run_at.nil? && !step.ready_to_run?(step_map) }
      end
    end
  end
end
