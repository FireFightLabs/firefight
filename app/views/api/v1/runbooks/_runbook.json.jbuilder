json.(runbook, :slug, :name, :summary, :external_url, :aliases)

json.content runbook.content if local_assigns[:full]

json.steps runbook.runbook_steps do |step|
  json.(step, :position, :title, :instruction, :tool, :arguments)
end

parts = runbook.readable_parts
json.inputs parts.inputs
json.watch parts.watch
workflow = runbook.workflow_for_agents
json.workflow workflow.merge(said: local_assigns[:workflow_said]).compact if workflow

json.created_at runbook.created_at.utc.iso8601
json.updated_at runbook.updated_at.utc.iso8601
