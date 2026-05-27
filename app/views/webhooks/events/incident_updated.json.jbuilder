json.partial! "webhooks/shared/envelope"

json.data do
  json.incident do
    json.partial! "webhooks/shared/incident", incident: @event.incident
  end

  json.changed_fields @event.changed_fields

  current = @event.eventable.is_a?(IncidentUpdate) ? @event.eventable : nil
  previous = current && IncidentUpdate
    .where(incident_id: current.incident_id)
    .where("created_at < ?", current.created_at)
    .order(created_at: :desc)
    .first

  if current && @event.changed_fields.any?
    json.changes do
      @event.changed_fields.each do |field|
        json.set! field do
          json.before previous&.public_send(field)
          json.after current.public_send(field)
        end
      end
    end
  else
    json.changes({})
  end

  if @event.user
    json.actor do
      json.partial! "webhooks/shared/actor", actor: @event.user
    end
  else
    json.actor nil
  end
end
