# The one section that is never empty. Built from the incident's own events
# rather than asked of the model, so every line is something that happened.
module Postmortem::TimelineSection
  MAX_EVENTS = 200

  def self.markdown(incident)
    events = incident.incident_events.undismissed.chronological.includes(:actor).to_a
    elided = [ events.size - MAX_EVENTS, 0 ].max
    lines = events.last(MAX_EVENTS).map do |event|
      "- **#{event.created_at.utc.strftime('%Y-%m-%d %H:%M UTC')}** #{event.actor_name} #{event.description}"
    end
    lines.unshift("_#{elided} earlier #{'event'.pluralize(elided)} not shown._") if elided.positive?
    lines.join("\n")
  end
end
