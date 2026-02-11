module Workflow::Cancellable
  extend ActiveSupport::Concern


  def cancel!(reason:, by:)
    transaction do
      current_time = Time.current
      update!(
        state: :cancelled,
        cancelled_by: by,
        cancellation_reason: reason,
        completed_at: current_time,
        state_timestamps: (state_timestamps || {}).merge("cancelled" => current_time.iso8601)
      )

      workflow_steps.where(status: %i[pending running]).update_all(
        status: :cancelled,
        completed_at: current_time
      )

      record_event(WorkflowEvents::Workflow::CANCELLED, reason: reason, by: by)
    end
  end
end
