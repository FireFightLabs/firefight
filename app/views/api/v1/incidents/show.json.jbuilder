json.incident do
  json.partial! "api/v1/incidents/incident", incident: @incident
end
