json.partial! "webhooks/shared/envelope"

json.data do
  json.incident do
    json.partial! "webhooks/shared/incident", incident: @event.incident
  end

  json.runbook do
    json.id @event.metadata["runbook_id"]
    json.slug @event.metadata["runbook_slug"]
    json.name @event.metadata["runbook_name"]
  end

  if @event.actor
    json.actor do
      json.partial! "webhooks/shared/actor", actor: @event.actor
    end
  else
    json.actor nil
  end
end
