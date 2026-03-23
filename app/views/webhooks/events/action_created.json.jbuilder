json.partial! "webhooks/shared/envelope"

json.data do
  json.incident do
    json.partial! "webhooks/shared/incident", incident: @event.incident
  end

  if @event.eventable.is_a?(IncidentActionUpdate)
    json.action do
      json.partial! "webhooks/shared/action", action: @event.eventable.incident_action
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
