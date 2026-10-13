json.runbook do
  json.partial! "api/v1/runbooks/runbook", runbook: @runbook, full: true, workflow_said: @workflow_said
end
