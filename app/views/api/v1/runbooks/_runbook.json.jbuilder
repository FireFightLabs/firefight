json.(runbook, :slug, :name, :summary, :external_url, :aliases)

json.content runbook.content if local_assigns[:full]

json.steps runbook.runbook_steps do |step|
  json.(step, :position, :title, :instruction, :tool, :arguments)
end

json.inputs runbook.inputs
json.watch runbook.watch

json.created_at runbook.created_at.utc.iso8601
json.updated_at runbook.updated_at.utc.iso8601
