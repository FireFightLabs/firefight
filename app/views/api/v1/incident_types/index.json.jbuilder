json.incident_types @incident_types do |incident_type|
  json.(incident_type, :id, :name, :slug, :position)
end
