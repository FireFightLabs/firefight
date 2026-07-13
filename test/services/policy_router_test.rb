require "test_helper"

class PolicyRouterTest < ActiveSupport::TestCase
  fixtures :workspaces

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @policy = Policy.create!(workspace: @workspace, domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
  end

  def rule!(priority, conditions, outcome = { action: "auto_create_incident" })
    @policy.policy_rules.create!(priority: priority, conditions: conditions, outcome: outcome)
  end

  test "first matching rule wins and evaluation halts" do
    rule!(1, [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "billing" ] } ], { action: "drop" })
    second = rule!(2, [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "auth_service" ] } ], { action: "auto_create_incident" })
    rule!(3, [], { action: "notify_only" })

    result = PolicyRouter.evaluate(@policy, { service: "auth_service" })

    assert result.matched?
    assert_equal second, result.matched_rule
    assert_equal "auto_create_incident", result.outcome["action"]
    assert_equal 2, result.trace.size
  end

  test "conditions within a rule are ANDed" do
    rule!(1, [
      { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "auth_service" ] },
      { field: "environment", operator: PolicyRule::OPERATOR_STARTS_WITH, value: "prod" }
    ])

    assert_not PolicyRouter.evaluate(@policy, { service: "auth_service", environment: "staging" }).matched?
    assert PolicyRouter.evaluate(@policy, { service: "auth_service", environment: "production" }).matched?
  end

  test "empty conditions act as a catch-all" do
    rule!(1, [], { action: "notify_only" })
    result = PolicyRouter.evaluate(@policy, {})
    assert result.matched?
  end

  test "operators match and reject correctly, including missing fields" do
    rule!(1, [ { field: "title", operator: PolicyRule::OPERATOR_CONTAINS, value: "checkout" } ])
    assert PolicyRouter.evaluate(@policy, { title: "checkout failing" }).matched?
    assert_not PolicyRouter.evaluate(@policy, { title: "login failing" }).matched?
    assert_not PolicyRouter.evaluate(@policy, {}).matched?
  end

  test "matches_regex matches with a timeout guard" do
    rule!(1, [ { field: "monitor", operator: PolicyRule::OPERATOR_MATCHES_REGEX, value: "^db-\\d+$" } ])
    assert PolicyRouter.evaluate(@policy, { monitor: "db-42" }).matched?
    assert_not PolicyRouter.evaluate(@policy, { monitor: "web-42" }).matched?
  end

  test "is_empty matches blank and missing values" do
    rule!(1, [ { field: "team", operator: PolicyRule::OPERATOR_IS_EMPTY } ])
    assert PolicyRouter.evaluate(@policy, {}).matched?
    assert PolicyRouter.evaluate(@policy, { team: "" }).matched?
    assert_not PolicyRouter.evaluate(@policy, { team: "platform" }).matched?
  end

  test "context keys and values are normalized to strings" do
    rule!(1, [ { field: "severity", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "1" ] } ])
    assert PolicyRouter.evaluate(@policy, { severity: 1 }).matched?
  end

  test "disabled policy never matches" do
    rule!(1, [], { action: "notify_only" })
    @policy.update!(enabled: false)

    result = PolicyRouter.evaluate(@policy, {})
    assert_not result.matched?
    assert_empty result.trace
  end

  test "no match returns full trace with per-condition results" do
    rule!(1, [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "billing" ] } ])
    result = PolicyRouter.evaluate(@policy, { service: "auth_service" })

    assert_not result.matched?
    assert_nil result.outcome
    entry = result.trace.first
    assert_equal false, entry[:matched]
    condition = entry[:conditions].first
    assert_equal "service", condition[:field]
    assert_equal "auth_service", condition[:actual]
    assert_equal false, condition[:matched]
  end
end
