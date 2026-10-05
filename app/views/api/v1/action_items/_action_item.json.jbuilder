json.(action_item, :id, :description, :status)
json.kind action_item.action_type
json.incident_id action_item.incident_id
json.external_key action_item.external_key
json.external_url action_item.external_url
json.issue_status action_item.issue_status_text

json.created_by do
  json.partial! "shared/actor", actor: action_item.created_by
end

if action_item.assignee
  json.assignee do
    json.partial! "shared/actor", actor: action_item.assignee
  end
else
  json.assignee nil
end

json.created_at action_item.created_at.utc.iso8601
