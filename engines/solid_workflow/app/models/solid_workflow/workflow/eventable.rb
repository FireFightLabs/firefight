module SolidWorkflow
  class Workflow < Record
    module Eventable
      extend ActiveSupport::Concern

      def record_event(event_type, step: nil, **metadata)
        events.create!(
          event_type: event_type,
          step: step,
          metadata: metadata
        )
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
