json.partial! "shared/incident", incident: incident
json.(incident, :channel_id, :channel_name)
