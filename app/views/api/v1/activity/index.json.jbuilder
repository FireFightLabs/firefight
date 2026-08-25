json.activity @invocations do |invocation|
  json.(invocation, :id, :action_key, :decision, :outcome, :error_summary, :duration_ms, :scope, :source, :approval_id)
  json.principal invocation.principal_label
  json.created_at invocation.created_at.utc.iso8601
  json.completed_at invocation.completed_at&.utc&.iso8601
end
json.pagination @pagination
