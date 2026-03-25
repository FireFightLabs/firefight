json.(incident, :id, :identifier, :name, :summary)
json.visibility incident.is_private ? "private" : "public"

json.status do
  json.(incident.incident_status, :id, :name)
  json.lifecycle_stage incident.incident_status.incident_lifecycle_stage.key
end

json.severity do
  json.(incident.incident_severity, :id, :name, :rank)
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
    json.id incident.lead.id
    json.name incident.lead.user.name
    json.email incident.lead.user.email
  end
else
  json.lead nil
end

json.declared_by do
  json.id incident.declared_by.id
  json.name incident.declared_by.user.name
  json.email incident.declared_by.user.email
end

json.declared_at incident.declared_at&.utc&.iso8601
json.detected_at incident.detected_at&.utc&.iso8601
json.resolved_at incident.resolved_at&.utc&.iso8601
json.created_at incident.created_at.utc.iso8601
json.updated_at incident.updated_at.utc.iso8601
json.custom_fields incident.custom_fields
