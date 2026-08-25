json.(approval, :id, :action_key, :scope, :params, :required_role, :status, :source)
json.principal approval.principal_label
json.self_approvable approval.self_approvable
json.approvers approval.approver_ids
json.approver approval.approver&.display_name
json.requested_at approval.created_at.utc.iso8601
json.resolved_at approval.resolved_at&.utc&.iso8601
