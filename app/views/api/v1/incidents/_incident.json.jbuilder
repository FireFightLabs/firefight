json.partial! "shared/incident", incident: incident
json.visibility incident.is_private ? "private" : "public"
