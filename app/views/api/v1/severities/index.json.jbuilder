json.severities @severities do |severity|
  json.(severity, :id, :name, :slug, :rank, :position, :is_default)
end
