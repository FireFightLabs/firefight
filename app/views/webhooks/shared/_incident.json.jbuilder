json.(incident, :id, :identifier, :name, :summary, :channel_id, :channel_name)
json.declared_at incident.declared_at&.utc&.iso8601
json.detected_at incident.detected_at&.utc&.iso8601
json.resolved_at incident.resolved_at&.utc&.iso8601

json.status do
  json.(incident.incident_status, :id, :name)
end

json.severity do
  json.(incident.incident_severity, :id, :name)
end

if incident.incident_type
  json.type do
    json.(incident.incident_type, :id, :name)
  end
else
  json.type nil
end

if incident.lead
  json.lead do
    json.partial! "webhooks/shared/actor", actor: incident.lead
  end
else
  json.lead nil
end

json.declared_by do
  json.partial! "webhooks/shared/actor", actor: incident.declared_by
end

json.custom_fields incident.custom_fields
