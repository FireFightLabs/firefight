json.partial! "webhooks/shared/envelope"

json.data do
  json.incident do
    json.partial! "webhooks/shared/incident", incident: @event.incident
  end

  if @event.incident.lead
    json.lead do
      json.partial! "webhooks/shared/actor", actor: @event.incident.lead
    end
  else
    json.lead nil
  end

  if @event.user
    json.actor do
      json.partial! "webhooks/shared/actor", actor: @event.user
    end
  else
    json.actor nil
  end
end
