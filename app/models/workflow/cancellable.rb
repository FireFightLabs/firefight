module Workflow::Cancellable
  extend ActiveSupport::Concern


  def cancel!(reason:, by:)
    transaction do
      update!(
        state: :cancelled,
        cancelled_by: by,
        cancellation_reason: reason,
        completed_at: Time.current
      )

    workflow_steps.where(status: :pending).update_all(status: :cancelled)
      record_event(WorkflowEvents::Workflow::CANCELLED, reason: reason, by: by)
    end
  end
end
