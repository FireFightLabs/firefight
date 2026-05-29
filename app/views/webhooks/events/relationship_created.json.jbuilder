json.partial! "webhooks/shared/envelope"

json.data do
  json.incident do
    json.partial! "webhooks/shared/incident", incident: @event.incident
  end

  json.related_incident do
    json.id @event.metadata["related_incident_id"]
    json.identifier @event.metadata["related_identifier"]
  end

  if @event.actor
    json.actor do
      json.partial! "webhooks/shared/actor", actor: @event.actor
    end
  else
    json.actor nil
  end
end
