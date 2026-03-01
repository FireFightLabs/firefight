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
        workflow.record_event(SolidWorkflow::Events::Step::FAILED, step: self, error: error.message)

        if should_retry?
          schedule_retry!
        else
          update!(status: :failed, completed_at: Time.current)
        end
      end

      private

      def format_error(error)
        "#{error.class}: #{error.message}\n#{error.backtrace.first(5).join("\n")}"
      end
    end
  end
end
