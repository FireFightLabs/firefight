module SolidWorkflow
  class Workflow < Record
    module Pausable
      extend ActiveSupport::Concern

      def pause!(reason: nil, by: nil)
        return if completed?

        transaction do
          current_time = Time.current
          update!(
            state: :paused,
            paused_at: current_time,
            paused_by: by,
            pause_reason: reason,
            resumed_at: nil,
            resumed_by: nil,
            state_timestamps: (state_timestamps || {}).merge("paused" => current_time.iso8601)
          )

          record_event(SolidWorkflow::Events::Workflow::PAUSED, reason: reason, by: by)
        end

        Rails.logger.info({
          event: "workflow.paused",
          workflow_id: id,
          workflow_class: workflow_class,
          reason: reason,
          by: by
        })
      end

      def resume!(by: nil)
        return unless paused?

        transaction do
          current_time = Time.current
          update!(
            state: :running,
            resumed_at: current_time,
            resumed_by: by,
            state_timestamps: (state_timestamps || {}).merge("running" => current_time.iso8601)
          )

          record_event(SolidWorkflow::Events::Workflow::RESUMED, by: by)
        end

        Rails.logger.info({
          event: "workflow.resumed",
          workflow_id: id,
          workflow_class: workflow_class,
          by: by,
          paused_duration_seconds: paused_duration
        })

        enqueue_next_steps
      end

      def pause_metadata
        return nil unless paused_at

        {
          paused_at: paused_at,
          paused_by: paused_by,
          pause_reason: pause_reason,
          resumed_at: resumed_at,
          resumed_by: resumed_by
        }
      end

      def paused_duration
        return nil unless paused_at

        ((resumed_at || Time.current) - paused_at).to_f
      end
    end
  end
end
