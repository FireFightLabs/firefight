json.runbooks @runbooks do |runbook|
  json.partial! "api/v1/runbooks/runbook", runbook: runbook
end
