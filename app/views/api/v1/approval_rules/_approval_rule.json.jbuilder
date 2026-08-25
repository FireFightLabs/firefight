requirement = PolicyRule::ApprovalOutcome.requirement(approval_rule.outcome)
environment_ids = PolicyRule::ApprovalConditions.values_for(approval_rule.conditions, PolicyRule::ApprovalConditions::FIELD_ENVIRONMENT)

json.(approval_rule, :id, :priority, :enabled)
json.abilities PolicyRule::ApprovalConditions.values_for(approval_rule.conditions, PolicyRule::ApprovalConditions::FIELD_ACTION_KEY)
json.risk_levels PolicyRule::ApprovalConditions.values_for(approval_rule.conditions, PolicyRule::ApprovalConditions::FIELD_RISK_LEVEL)
json.environments approval_rule.policy.workspace.environment_entries.where(id: environment_ids).pluck(:slug)
json.approver_role requirement["role"]
json.approvers Array(requirement["approvers"])
json.notify requirement["notify"] || PolicyRule::ApprovalOutcome::NOTIFY_CHANNEL
json.self_approval requirement.fetch("self_approval", true)
json.created_at approval_rule.created_at.utc.iso8601
json.updated_at approval_rule.updated_at.utc.iso8601
