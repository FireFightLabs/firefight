class ApprovalRuleSerializer < BaseSerializer
  object_as :rule

  NOTIFY_UNION = PolicyRule::ApprovalOutcome::NOTIFY_OPTIONS.map(&:inspect).join(" | ")

  type :string
  def id
    rule.id
  end

  attributes(
    priority: { type: :number },
    enabled: { type: :boolean }
  )

  type "string[]"
  def action_keys
    PolicyRule::ApprovalConditions.values_for(rule.conditions, PolicyRule::ApprovalConditions::FIELD_ACTION_KEY)
  end

  type "string[]"
  def risk_levels
    PolicyRule::ApprovalConditions.values_for(rule.conditions, PolicyRule::ApprovalConditions::FIELD_RISK_LEVEL)
  end

  type "string[]"
  def environments
    PolicyRule::ApprovalConditions.values_for(rule.conditions, PolicyRule::ApprovalConditions::FIELD_ENVIRONMENT)
  end

  type :string
  def role
    requirement["role"].to_s
  end

  type :boolean
  def self_approval
    requirement.fetch("self_approval", true)
  end

  type NOTIFY_UNION
  def notify
    requirement["notify"] || PolicyRule::ApprovalOutcome::NOTIFY_CHANNEL
  end

  type "string[]"
  def approver_ids
    Array(requirement["approvers"]).map(&:to_s)
  end

  private

  def requirement
    PolicyRule::ApprovalOutcome.requirement(rule.outcome)
  end
end
