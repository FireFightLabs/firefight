json.(approval, :id, :action_key, :scope, :params, :required_role, :status, :source)
json.principal approval.principal_label
json.self_approvable approval.self_approvable
json.approvers Ability::Principal.references(approval.approver_ids)
json.agents_may_approve approval.agents_may_approve
json.approver approval.approver&.actor_display_name
json.requested_at approval.created_at.utc.iso8601
json.resolved_at approval.resolved_at&.utc&.iso8601
