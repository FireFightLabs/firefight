module SolidWorkflow
  class Step < Record
    module Executable
      extend ActiveSupport::Concern

      def execute!
        return if workflow.cancelled?
        return if succeeded? || cancelled?

        reload
        seen_wakes = wake_requests

        runner = workflow.workflow_klass.new
        result = runner.run_step(
          name,
          workflow: workflow,
          step: self,
          input: input
        )

        workflow.reload
        if workflow.cancelled?
          SolidWorkflow::Step.where(id: id, status: :running).update_all(
            status: :cancelled,
            completed_at: Time.current,
            updated_at: Time.current
          )
          reload
          return
        end

        return park!(result, seen_wakes: seen_wakes) if result.is_a?(SolidWorkflow::Park)

        output, route = result.is_a?(SolidWorkflow::Routed) ? [ result.output, result.route ] : [ result, nil ]
        current_updated_at = updated_at
        rows_updated = SolidWorkflow::Step.where(
          id: id,
          status: :running,
          updated_at: current_updated_at
        ).update_all(
          status: :succeeded,
          output: output || {},
          route: route,
          completed_at: Time.current,
          updated_at: Time.current
        )

        if rows_updated == 0
          reload
          # Cancelled, timed out or reset by the sweeper while it ran, and whoever moved it owns what happens next.
          return unless running?
          raise "Step status changed unexpectedly during execution"
        end

        reload
        workflow.record_event(SolidWorkflow::Events::Step::SUCCEEDED, step: self)
      end

      # With a guard, such as the job that claimed the step, only a step still running under that guard moves, so a job
      # whose attempt timed out never fails the attempt that replaced it.
      def mark_failed!(error, **guard)
        return mark_failed_guarded!(error, guard) if guard.any?

        update!(last_error: format_error(error))

        if should_retry?(error)
          workflow.record_event(SolidWorkflow::Events::Step::ATTEMPT_FAILED, step: self, error: truncate_error(error.message))
          schedule_retry!
        else
          update!(status: :failed, completed_at: Time.current)
          workflow.record_event(SolidWorkflow::Events::Step::FAILED, step: self, error: truncate_error(error.message))
        end
      end

      def mark_failed_guarded!(error, guard)
        held = SolidWorkflow::Step.where(id: id, status: :running, **guard)
        message = truncate_error(error.message)

        if should_retry?(error)
          delay = calculate_backoff
          return false unless held.update_all(status: :pending, run_at: Time.current + delay, last_error: format_error(error),
                                              claimed_by: nil, timeout_at: nil, updated_at: Time.current) == 1

          reload
          workflow.record_event(SolidWorkflow::Events::Step::ATTEMPT_FAILED, step: self, error: message)
          workflow.record_event(SolidWorkflow::Events::Step::RETRY_SCHEDULED, step: self, delay: delay, attempt: attempts)
        else
          return false unless held.update_all(status: :failed, completed_at: Time.current, last_error: format_error(error),
                                              timeout_at: nil, updated_at: Time.current) == 1

          reload
          workflow.record_event(SolidWorkflow::Events::Step::FAILED, step: self, error: message)
        end
        true
      end

      private

      MAX_ERROR_MESSAGE_BYTES = 2_000

      def format_error(error)
        cleaner = Rails.respond_to?(:backtrace_cleaner) ? Rails.backtrace_cleaner : nil
        backtrace = cleaner ? cleaner.clean(error.backtrace || []).first(10) : Array(error.backtrace).first(10)
        "#{error.class}: #{truncate_error(error.message)}\n#{backtrace.join("\n")}"
      end

      def truncate_error(message)
        return message if message.to_s.bytesize <= MAX_ERROR_MESSAGE_BYTES
        message.byteslice(0, MAX_ERROR_MESSAGE_BYTES) + "…[truncated]"
      end
    end
  end
end
