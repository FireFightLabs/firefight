json.partial! "webhooks/shared/envelope"

json.data do
  json.incident do
    json.partial! "webhooks/shared/incident", incident: @event.incident
  end

  if @event.incident.postmortem
    postmortem = @event.incident.postmortem
    json.postmortem do
      json.(postmortem, :id, :title, :status)
    end
  end

  if @event.actor
    json.actor do
      json.partial! "webhooks/shared/actor", actor: @event.actor
    end
  else
    json.actor nil
  end
end
