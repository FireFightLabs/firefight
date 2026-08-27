json.incident_id @incident.id
json.messages @page.messages do |message|
  json.message_id message.message_id
  json.thread_id message.thread_id
  json.said_at message.posted_at.utc.iso8601
  json.text message.content
  json.redacted message.scrubbed
  if message.workspace_membership
    json.said_by do
      json.partial! "shared/actor", actor: message.workspace_membership
    end
  else
    json.said_by nil
  end
end
json.more_before @page.more_before
