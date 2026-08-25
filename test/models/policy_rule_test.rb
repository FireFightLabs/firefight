require "test_helper"

class PolicyRuleTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @policy = Policy.create!(workspace: @workspace, domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
  end

  test "valid rule with each operator" do
    rule = @policy.policy_rules.build(
      priority: 1,
      conditions: [
        { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "auth_service" ] },
        { field: "title", operator: PolicyRule::OPERATOR_CONTAINS, value: "checkout" },
        { field: "environment", operator: PolicyRule::OPERATOR_STARTS_WITH, value: "prod" },
        { field: "monitor", operator: PolicyRule::OPERATOR_MATCHES_REGEX, value: "^db-.*$" },
        { field: "team", operator: PolicyRule::OPERATOR_IS_EMPTY }
      ],
      outcome: { action: "auto_create_incident" }
    )
    assert rule.valid?
  end

  test "empty conditions are valid (catch-all rule)" do
    rule = @policy.policy_rules.build(priority: 99, conditions: [], outcome: { action: "drop" })
    assert rule.valid?
  end

  test "rejects non-array conditions" do
    rule = @policy.policy_rules.build(priority: 1, conditions: { field: "x" })
    assert_not rule.valid?
    assert_includes rule.errors[:conditions].join, "must be a list of conditions"
  end

  test "rejects unknown operator" do
    rule = @policy.policy_rules.build(priority: 1, conditions: [ { field: "service", operator: "equals", value: "x" } ])
    assert_not rule.valid?
    assert_includes rule.errors[:conditions].join, "Condition 1 has an unknown operator"
  end

  test "rejects condition without field" do
    rule = @policy.policy_rules.build(priority: 1, conditions: [ { operator: PolicyRule::OPERATOR_IS_EMPTY } ])
    assert_not rule.valid?
    assert_includes rule.errors[:conditions].join, "Condition 1 needs a field"
  end

  test "is_one_of requires a non-empty array value" do
    rule = @policy.policy_rules.build(priority: 1, conditions: [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: "auth" } ])
    assert_not rule.valid?

    rule.conditions = [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [] } ]
    assert_not rule.valid?
  end

  test "contains requires a string value" do
    rule = @policy.policy_rules.build(priority: 1, conditions: [ { field: "title", operator: PolicyRule::OPERATOR_CONTAINS, value: [ "x" ] } ])
    assert_not rule.valid?
  end

  test "rejects invalid regex at write time" do
    rule = @policy.policy_rules.build(priority: 1, conditions: [ { field: "title", operator: PolicyRule::OPERATOR_MATCHES_REGEX, value: "([" } ])
    assert_not rule.valid?
    assert_includes rule.errors[:conditions].join, "Condition 1 has a pattern Firefight cannot read"
  end

  test "priority is unique per policy" do
    @policy.policy_rules.create!(priority: 1, conditions: [], outcome: { "action" => PolicyRule::AlertRoutingOutcome::ACTION_DROP })
    duplicate = @policy.policy_rules.build(priority: 1, conditions: [], outcome: { "action" => PolicyRule::AlertRoutingOutcome::ACTION_DROP })
    assert_not duplicate.valid?
  end

  test "approval outcomes name a role, where to ask, and members of the workspace as approvers" do
    workspace = workspaces(:slack_workspace_one)
    policy = workspace.policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals")
    base = { "role" => WorkspaceMembership.roles[:admin], "count" => 1 }

    rule = policy.policy_rules.new(priority: 1, conditions: [], outcome: { "require" => base })
    assert rule.valid?

    rule.outcome = { "require" => base.merge("notify" => "smoke signal") }
    assert_not rule.valid?
    assert_match "notify", rule.errors[:outcome].join

    rule.outcome = { "require" => base.merge("approvers" => [ workspace_memberships(:alice_workspace_two).id ]) }
    assert_not rule.valid?
    assert_match "of this workspace", rule.errors[:outcome].join

    rule.outcome = { "require" => base.merge("approvers" => [ workspace_memberships(:bob_workspace_one).id ], "notify" => "dm") }
    assert rule.valid?

    agent = workspace.agents.create!(name: "Grok", slug: "grok")
    rule.outcome = { "require" => base.merge("approvers" => [ { "kind" => "agent", "id" => agent.id } ]) }
    assert_not rule.valid?
    assert_match "agents_may_approve", rule.errors[:outcome].join

    rule.outcome = { "require" => base.merge("approvers" => [ { "kind" => "agent", "id" => agent.id } ], "agents_may_approve" => true) }
    assert rule.valid?
  end

  test "approval conditions round-trip through the three dialog questions" do
    conditions = PolicyRule::ApprovalConditions.build(
      action_keys: [ "catalog.delete", "" ], risk_levels: [], environments: [ "env-1" ]
    )

    assert_equal 2, conditions.size
    assert_equal [ "catalog.delete" ], PolicyRule::ApprovalConditions.values_for(conditions, "action_key")
    assert_equal [], PolicyRule::ApprovalConditions.values_for(conditions, "risk_level")
    assert_equal [ "env-1" ], PolicyRule::ApprovalConditions.values_for(conditions, "environment")
  end
end
