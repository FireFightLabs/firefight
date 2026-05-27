json.partial! "webhooks/shared/envelope"

json.data do
  json.incident do
    json.partial! "webhooks/shared/incident", incident: @event.incident
  end

  json.changed_fields @event.changed_fields

  if @event.incident.postmortem
    postmortem = @event.incident.postmortem
    json.postmortem do
      json.(postmortem, :id, :title, :status)
    end
  end

  if @event.user
    json.actor do
      json.partial! "webhooks/shared/actor", actor: @event.user
    end
  else
    json.actor nil
  end
end
