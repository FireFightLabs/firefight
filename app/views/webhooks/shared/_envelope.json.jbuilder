json.id @delivery_id
json.event_type @event.event_type
json.workspace_id @event.incident.workspace_id
json.occurred_at @event.created_at.utc.iso8601
