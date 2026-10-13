module SolidWorkflow
  class Workflow < Record
    module Cancellable
      extend ActiveSupport::Concern

      def cancel!(reason:, by:)
        transaction do
          return false unless transition!(:cancelled, from: %i[pending running waiting paused], cancelled_by: by, cancellation_reason: reason)

          steps.where(status: %i[pending running waiting]).update_all(
            status: :cancelled,
            completed_at: completed_at
          )

          record_event(SolidWorkflow::Events::Workflow::CANCELLED, reason: reason, by: by)
          cancel_children!(reason: reason, by: by)
          true
        end
      end

      # Sub workflows and for each items this run started end with it.
      def cancel_children!(reason:, by:, step_ids: steps.select(:id))
        SolidWorkflow::Workflow.where(parent_step_id: step_ids).where.not(state: Stateable::TERMINAL_STATES).find_each do |child|
          child.cancel!(reason: reason, by: by)
        end
      end
    end
  end
end
