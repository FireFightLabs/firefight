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
          current_time = Time.current
          current_updated_at = updated_at
          rows_updated = SolidWorkflow::Workflow.where(
            id: id,
            state: [ :pending, :running ],
            updated_at: current_updated_at
          ).update_all(
            state: :succeeded,
            completed_at: current_time,
            updated_at: current_time,
            state_timestamps: state_timestamps_merge_sql("succeeded", current_time)
          )

          if rows_updated > 0
            reload
            record_event(SolidWorkflow::Events::Workflow::SUCCEEDED)
          end

        elsif all_steps.any? { |s| s.failed? && s.attempts >= s.max_attempts }
          current_time = Time.current
          current_updated_at = updated_at
          rows_updated = SolidWorkflow::Workflow.where(
            id: id,
            state: [ :pending, :running ],
            updated_at: current_updated_at
          ).update_all(
            state: :failed,
            completed_at: current_time,
            updated_at: current_time,
            state_timestamps: state_timestamps_merge_sql("failed", current_time)
          )

          if rows_updated > 0
            reload
            record_event(SolidWorkflow::Events::Workflow::FAILED)
          end

        elsif pending?
          current_time = Time.current
          current_updated_at = updated_at
          rows_updated = SolidWorkflow::Workflow.where(
            id: id,
            state: :pending,
            updated_at: current_updated_at
          ).update_all(
            state: :running,
            started_at: current_time,
            updated_at: current_time,
            state_timestamps: state_timestamps_merge_sql("running", current_time)
          )

          reload if rows_updated > 0
        end
      end

      def state_timestamps_merge_sql(state, timestamp)
        state_value = SolidWorkflow::Workflow.connection.quote(state.to_s)
        timestamp_value = SolidWorkflow::Workflow.connection.quote(timestamp.iso8601)
        Arel.sql("coalesce(state_timestamps, '{}'::jsonb) || jsonb_build_object(#{state_value}, #{timestamp_value})")
      end
    end
  end
end
