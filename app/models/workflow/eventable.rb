module Workflow::Eventable
  extend ActiveSupport::Concern

  def record_event(event_type, step: nil, **metadata)
    workflow_events.create!(
      event_type: event_type,
      workflow_step: step,
      metadata: metadata
    )
  end

  def timeline
    workflow_events.order(:created_at).map do |event|
      {
        timestamp: event.created_at,
        type: event.event_type,
        step: event.workflow_step&.name,
        metadata: event.metadata
      }
    end
  end
end
