json.(action, :id, :description, :action_type, :status)

if action.assignee
  json.assignee do
    json.partial! "webhooks/shared/actor", actor: action.assignee
  end
else
  json.assignee nil
end
