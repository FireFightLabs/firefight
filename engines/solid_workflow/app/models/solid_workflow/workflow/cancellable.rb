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

      # A Stop step ending the run as succeeded leaves every other step not yet run as bypassed, in one statement each,
      # and cancels the runs the waiting ones started.
      def stop_others!(stopping)
        others = steps.where.not(id: stopping.id).where(status: %i[pending waiting]).to_a
        waiting = others.select(&:waiting?).map(&:id)
        now = Time.current
        others.each do |other|
          moved = SolidWorkflow::Step.where(id: other.id, status: other.status).update_all(status: :bypassed, completed_at: now, updated_at: now) == 1
          record_event(SolidWorkflow::Events::Step::BYPASSED, step: other) if moved
        end
        cancel_children!(reason: "stopped", by: nil, step_ids: waiting) if waiting.any?
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
