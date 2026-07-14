require "test_helper"

class PolicyEvaluationTest < ActiveSupport::TestCase
  fixtures :workspaces

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @policy = Policy.create!(workspace: @workspace, domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
  end

  def rule!(priority, conditions, outcome = { "action" => PolicyRule::AlertRoutingOutcome::ACTION_AUTO_CREATE })
    @policy.policy_rules.create!(priority: priority, conditions: conditions, outcome: outcome)
  end

  test "first matching rule wins and evaluation halts" do
    rule!(1, [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "billing" ] } ], { action: "drop" })
    second = rule!(2, [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "auth_service" ] } ], { action: "auto_create_incident" })
    rule!(3, [], { action: "notify_only" })

    result = @policy.evaluate({ service: "auth_service" })

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

    assert_not @policy.evaluate({ service: "auth_service", environment: "staging" }).matched?
    assert @policy.evaluate({ service: "auth_service", environment: "production" }).matched?
  end

  test "empty conditions act as a catch-all" do
    rule!(1, [], { action: "notify_only" })
    result = @policy.evaluate({})
    assert result.matched?
  end

  test "operators match and reject correctly, including missing fields" do
    rule!(1, [ { field: "title", operator: PolicyRule::OPERATOR_CONTAINS, value: "checkout" } ])
    assert @policy.evaluate({ title: "checkout failing" }).matched?
    assert_not @policy.evaluate({ title: "login failing" }).matched?
    assert_not @policy.evaluate({}).matched?
  end

  test "matches_regex matches with a timeout guard" do
    rule!(1, [ { field: "monitor", operator: PolicyRule::OPERATOR_MATCHES_REGEX, value: "^db-\\d+$" } ])
    assert @policy.evaluate({ monitor: "db-42" }).matched?
    assert_not @policy.evaluate({ monitor: "web-42" }).matched?
  end

  test "is_empty matches blank and missing values" do
    rule!(1, [ { field: "team", operator: PolicyRule::OPERATOR_IS_EMPTY } ])
    assert @policy.evaluate({}).matched?
    assert @policy.evaluate({ team: "" }).matched?
    assert_not @policy.evaluate({ team: "platform" }).matched?
  end

  test "context keys and values are normalized to strings" do
    rule!(1, [ { field: "severity", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "1" ] } ])
    assert @policy.evaluate({ severity: 1 }).matched?
  end

  test "disabled rules are skipped but appear in the trace" do
    disabled = rule!(1, [], { action: "drop" })
    disabled.update!(enabled: false)
    live = rule!(2, [], { action: "notify_only" })

    result = @policy.evaluate({})

    assert_equal live, result.matched_rule
    skipped_entry = result.trace.find { |t| t[:rule_id] == disabled.id }
    assert skipped_entry[:skipped]
    assert_not skipped_entry[:matched]
  end

  test "disabled policy never matches" do
    rule!(1, [], { action: "notify_only" })
    @policy.update!(enabled: false)

    result = @policy.evaluate({})
    assert_not result.matched?
    assert_empty result.trace
  end

  test "no match returns full trace with per-condition results" do
    rule!(1, [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "billing" ] } ])
    result = @policy.evaluate({ service: "auth_service" })

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
