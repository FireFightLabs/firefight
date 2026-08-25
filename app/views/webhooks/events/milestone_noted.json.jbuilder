json.partial! "webhooks/shared/envelope"

json.data do
  json.incident do
    json.partial! "webhooks/shared/incident", incident: @event.incident
  end

  json.note do
    json.id @event.id
    json.kind @event.metadata["kind"]
    json.statement @event.metadata["statement"]
    json.said_by @event.metadata["member_name"]
    json.said_at @event.metadata["said_at"]
    json.message_text @event.metadata["message_text"]
    json.permalink @event.metadata["permalink"]
  end
end
