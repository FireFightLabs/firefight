require "test_helper"

class PolicyRuleTest < ActiveSupport::TestCase
  fixtures :workspaces

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
    assert_includes rule.errors[:conditions].join, "must be an array"
  end

  test "rejects unknown operator" do
    rule = @policy.policy_rules.build(priority: 1, conditions: [ { field: "service", operator: "equals", value: "x" } ])
    assert_not rule.valid?
    assert_includes rule.errors[:conditions].join, "unknown operator"
  end

  test "rejects condition without field" do
    rule = @policy.policy_rules.build(priority: 1, conditions: [ { operator: PolicyRule::OPERATOR_IS_EMPTY } ])
    assert_not rule.valid?
    assert_includes rule.errors[:conditions].join, "missing a field"
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
    assert_includes rule.errors[:conditions].join, "invalid regex"
  end

  test "priority is unique per policy" do
    @policy.policy_rules.create!(priority: 1, conditions: [], outcome: { "action" => PolicyRule::AlertRoutingOutcome::ACTION_DROP })
    duplicate = @policy.policy_rules.build(priority: 1, conditions: [], outcome: { "action" => PolicyRule::AlertRoutingOutcome::ACTION_DROP })
    assert_not duplicate.valid?
  end
end
