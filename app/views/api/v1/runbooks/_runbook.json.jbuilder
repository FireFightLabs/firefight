json.(runbook, :slug, :name, :summary, :external_url)

json.content runbook.content if local_assigns[:full]

json.steps runbook.runbook_steps do |step|
  json.(step, :position, :title, :instruction)
end

json.created_at runbook.created_at.utc.iso8601
json.updated_at runbook.updated_at.utc.iso8601
