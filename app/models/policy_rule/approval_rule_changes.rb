# Turns a partial description of an approval rule (the API and MCP shapes,
# environments by slug, only the keys that arrived) into the attributes the
# rule stores. Absent keys keep what the existing rule has, and a new rule
# without a role asks any admin, matching the dashboard's default.
module PolicyRule::ApprovalRuleChanges
  CONDITION_KEYS = %i[abilities risk_levels environments].freeze
  OUTCOME_KEYS = %i[approver_role self_approval notify approvers agents_may_approve].freeze

  def self.attributes(workspace:, existing:, changes:)
    changes = changes.to_h.symbolize_keys
    attrs = {}
    attrs[:enabled] = ActiveModel::Type::Boolean.new.cast(changes[:enabled]) if changes.key?(:enabled)

    if existing.nil? || CONDITION_KEYS.any? { |key| changes.key?(key) }
      attrs[:conditions] = PolicyRule::ApprovalConditions.build(
        action_keys: changes.key?(:abilities) ? changes[:abilities] : current(existing, PolicyRule::ApprovalConditions::FIELD_ACTION_KEY),
        risk_levels: changes.key?(:risk_levels) ? changes[:risk_levels] : current(existing, PolicyRule::ApprovalConditions::FIELD_RISK_LEVEL),
        environments: changes.key?(:environments) ? environment_ids(workspace, changes[:environments]) : current(existing, PolicyRule::ApprovalConditions::FIELD_ENVIRONMENT)
      )
    end

    if existing.nil? || OUTCOME_KEYS.any? { |key| changes.key?(key) }
      requirement = existing ? PolicyRule::ApprovalOutcome.requirement(existing.outcome) : {}
      attrs[:outcome] = PolicyRule::ApprovalOutcome.build(
        role: changes.fetch(:approver_role, requirement["role"] || WorkspaceMembership.roles[:admin]),
        self_approval: changes.fetch(:self_approval, requirement.fetch("self_approval", true)),
        notify: changes.fetch(:notify, requirement["notify"]),
        approvers: changes.key?(:approvers) ? changes[:approvers] : requirement["approvers"],
        agents_may_approve: changes.fetch(:agents_may_approve, requirement.fetch("agents_may_approve", false))
      )
    end

    attrs
  end

  def self.environment_ids(workspace, slugs)
    workspace.environment_entries.where(slug: Array(slugs).map(&:to_s)).pluck(:id)
  end

  def self.current(existing, field)
    existing ? PolicyRule::ApprovalConditions.values_for(existing.conditions, field) : []
  end
  private_class_method :current
end
