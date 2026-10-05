# Built from incident events, never from the model, so it is never empty.
module Postmortem::TimelineSection
  MAX_EVENTS = 200
  # An update is one line of the timeline. Its full text is in the incident's own timeline and in the model's input.
  MESSAGE_LEAD_LIMIT = 200
  CHANGE_VALUE_LIMIT = 80

  def self.markdown(incident)
    events = incident.incident_events.undismissed.chronological.includes(:actor, :eventable).to_a
    elided = [ events.size - MAX_EVENTS, 0 ].max
    shown = IncidentEvent.with_update_history(events.last(MAX_EVENTS))
    lines = shown.map { |event| entry(event) }
    lines.unshift("_#{elided} earlier #{'event'.pluralize(elided)} not shown._") if elided.positive?
    lines.join("\n")
  end

  def self.entry(event)
    line = "- **#{event.created_at.utc.strftime('%Y-%m-%d %H:%M UTC')}** #{event.actor_name} #{event.description}"
    details = event.update_changes.map { |change| change_text(change) }
    lead = IncidentUpdate::MessageText.lead(event.update_message, limit: MESSAGE_LEAD_LIMIT)
    details << lead if lead
    ([ line ] + details.map { |detail| "  - #{detail}" }).join("\n")
  end

  def self.change_text(change)
    before = value_text(change, change.before)
    after = value_text(change, change.after)
    if before && after then "#{change.label}: #{before} → #{after}"
    elsif after then "#{change.label} set to #{after}"
    else "#{change.label} cleared"
    end
  end

  def self.value_text(change, value)
    return nil if value.blank?
    return Time.iso8601(value).utc.strftime("%Y-%m-%d %H:%M UTC") if change.kind == IncidentUpdate::CHANGE_KIND_TIME

    IncidentUpdate::MessageText.lead(value, limit: CHANGE_VALUE_LIMIT)
  rescue ArgumentError
    value
  end
  private_class_method :entry, :change_text, :value_text
end
