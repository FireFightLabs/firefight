json.(incident, :id, :identifier, :name, :summary)

json.status do
  json.partial! "shared/incident_status", status: incident.incident_status
end

json.severity do
  json.partial! "shared/incident_severity", severity: incident.incident_severity
end

if incident.incident_type
  json.type do
    json.partial! "shared/incident_type", type: incident.incident_type
  end
else
  json.type nil
end

if incident.lead
  json.lead do
    json.partial! "shared/actor", actor: incident.lead
  end
else
  json.lead nil
end

json.source incident.source
json.test incident.is_test

if incident.declared_by
  json.declared_by do
    json.partial! "shared/actor", actor: incident.declared_by
  end
else
  json.declared_by nil
end

json.declared_at incident.declared_at&.utc&.iso8601
json.detected_at incident.detected_at&.utc&.iso8601
json.resolved_at incident.resolved_at&.utc&.iso8601
json.created_at incident.created_at.utc.iso8601
json.updated_at incident.updated_at.utc.iso8601
json.custom_fields incident.custom_fields
