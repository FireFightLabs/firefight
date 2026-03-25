json.incidents @incidents do |incident|
  json.partial! "api/v1/incidents/incident", incident: incident
end

json.pagination @pagination
