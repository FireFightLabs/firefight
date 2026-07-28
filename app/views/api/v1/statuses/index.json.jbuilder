json.statuses @statuses do |status|
  json.(status, :id, :name, :slug, :position, :is_default)
  json.lifecycle_stage status.incident_lifecycle_stage.key
end
