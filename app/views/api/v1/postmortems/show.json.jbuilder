json.(@postmortem, :id, :title, :status)
json.incident_id @incident.id
json.html @postmortem.html_content
json.generation_state @postmortem.generation_state
json.written_by do
  json.partial! "shared/actor", actor: @postmortem.generated_by
end
json.updated_at @postmortem.updated_at.utc.iso8601
