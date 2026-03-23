json.partial! "webhooks/shared/envelope"

json.data do
  json.incident do
    json.partial! "webhooks/shared/incident", incident: @event.incident
  end

  details = @event.details || {}
  json.duplicate_of do
    json.id details["related_incident_id"]
    json.identifier details["related_identifier"]
  end

  if @event.user
    json.actor do
      json.partial! "webhooks/shared/actor", actor: @event.user
    end
  else
    json.actor nil
  end
end
