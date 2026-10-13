module SolidWorkflow
  class Workflow < Record
    module Eventable
      extend ActiveSupport::Concern

      # Every move is told to the workflow's class as well, so a host can keep its own record of the run.
      def record_event(event_type, step: nil, **metadata)
        event = events.create!(
          event_type: event_type,
          step: step,
          metadata: metadata
        )
        workflow_klass&.observe(self, event)
        event
      end

      def timeline
        events.includes(:step).order(:created_at).map do |event|
          {
            timestamp: event.created_at,
            type: event.event_type,
            step: event.step&.name,
            metadata: event.metadata
          }
        end
      end
    end
  end
end
