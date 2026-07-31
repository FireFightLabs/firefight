json.partial! "webhooks/shared/envelope"

json.data do
  json.incident do
    json.partial! "webhooks/shared/incident", incident: @event.incident
  end

  json.role do
    json.id @event.metadata["role_id"]
    json.slug @event.metadata["role_slug"]
    json.name @event.metadata["role_name"]
  end

  if @event.metadata["member_id"]
    json.member do
      json.id @event.metadata["member_id"]
      json.name @event.metadata["member_name"]
    end
  else
    json.member nil
  end

  if @event.actor
    json.actor do
      json.partial! "webhooks/shared/actor", actor: @event.actor
    end
  else
    json.actor nil
  end
end
