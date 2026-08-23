module SolidWorkflow
  class Workflow < Record
    module Cancellable
      extend ActiveSupport::Concern

      def cancel!(reason:, by:)
        transaction do
          return false unless transition!(:cancelled, from: %i[pending running paused], cancelled_by: by, cancellation_reason: reason)

          steps.where(status: %i[pending running]).update_all(
            status: :cancelled,
            completed_at: completed_at
          )

          record_event(SolidWorkflow::Events::Workflow::CANCELLED, reason: reason, by: by)
          true
        end
      end
    end
  end
end
