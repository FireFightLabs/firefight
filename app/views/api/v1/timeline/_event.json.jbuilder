json.id event.id
json.event_type event.event_type
json.description event.description
json.automated event.automated?
json.occurred_at event.created_at.utc.iso8601

if event.actor
  json.actor do
    json.partial! "shared/actor", actor: event.actor
  end
else
  json.actor nil
end

if event.milestone?
  metadata = event.metadata.to_h
  json.milestone do
    json.kind metadata["kind"]
    json.statement metadata["statement"]
    json.said_by metadata["member_name"]
    json.said_at metadata["said_at"]
    json.message_text metadata["message_text"]
    json.permalink metadata["permalink"]
    json.dismissed_at metadata["dismissed_at"]
  end
else
  json.milestone nil
end
