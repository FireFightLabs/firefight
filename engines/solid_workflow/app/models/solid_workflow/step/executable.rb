module SolidWorkflow
  class Step < Record
    module Executable
      extend ActiveSupport::Concern

      def execute!
        return if workflow.cancelled?
        return if succeeded? || cancelled?

        reload

        runner = workflow.workflow_klass.new
        output = runner.run_step(
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

        current_updated_at = updated_at
        rows_updated = SolidWorkflow::Step.where(
          id: id,
          status: :running,
          updated_at: current_updated_at
        ).update_all(
          status: :succeeded,
          output: output || {},
          completed_at: Time.current,
          updated_at: Time.current
        )

        if rows_updated == 0
          reload
          return if cancelled? || workflow.cancelled?
          raise "Step status changed unexpectedly during execution"
        end

        reload
        workflow.record_event(SolidWorkflow::Events::Step::SUCCEEDED, step: self)
      end

      def mark_failed!(error)
        update!(last_error: format_error(error))

        if should_retry?
          workflow.record_event(SolidWorkflow::Events::Step::ATTEMPT_FAILED, step: self, error: truncate_error(error.message))
          schedule_retry!
        else
          update!(status: :failed, completed_at: Time.current)
          workflow.record_event(SolidWorkflow::Events::Step::FAILED, step: self, error: truncate_error(error.message))
        end
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
