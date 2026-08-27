json.runbook do
  json.partial! "api/v1/runbooks/runbook", runbook: @runbook, full: true
end
