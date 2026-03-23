json.partial! "webhooks/shared/envelope"

json.data do
  json.incident do
    json.partial! "webhooks/shared/incident", incident: @event.incident
  end

  details = @event.details || {}
  json.merged_into do
    json.id details["canonical_incident_id"]
    json.identifier details["canonical_identifier"]
  end

  if @event.user
    json.actor do
      json.partial! "webhooks/shared/actor", actor: @event.user
    end
  else
    json.actor nil
  end
end
