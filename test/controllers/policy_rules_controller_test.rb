require "test_helper"

class PolicyRulesControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  def create_rule!(policy, priority, action: AlertIngestService::ACTION_DROP)
    policy.policy_rules.create!(priority: priority, conditions: [], outcome: { "action" => action })
  end

  test "create appends a rule (and the policy) with the next priority" do
    post policy_rules_url, params: {
      rule: {
        conditions: [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "checkout" ] } ],
        outcome: { action: AlertIngestService::ACTION_AUTO_CREATE }
      }
    }

    policy = @workspace.policies.for_domain(Policy::DOMAIN_ALERT_ROUTING).first
    rule = policy.policy_rules.find_by!(priority: 1)
    assert_equal "checkout", rule.conditions.first["value"].first
    assert_equal AlertIngestService::ACTION_AUTO_CREATE, rule.outcome["action"]
  end

  test "create persists the notify channel display name alongside the id" do
    post policy_rules_url, params: {
      rule: {
        conditions: [],
        outcome: {
          action: AlertIngestService::ACTION_NOTIFY_ONLY,
          notify: { type: PolicyRule::AlertRoutingOutcome::TARGET_CHANNEL, channel_id: "C123", channel_name: "alerts-feed" }
        }
      }
    }

    policy = @workspace.policies.for_domain(Policy::DOMAIN_ALERT_ROUTING).first
    rule = policy.policy_rules.find_by!(priority: 1)
    assert_equal "C123", rule.outcome.dig("notify", "channel_id")
    assert_equal "alerts-feed", rule.outcome.dig("notify", "channel_name")
  end

  test "invalid conditions redirect back with errors" do
    post policy_rules_url, params: {
      rule: { conditions: [ { field: "service", operator: "equals", value: "x" } ], outcome: { action: AlertIngestService::ACTION_DROP } }
    }

    policy = @workspace.policies.for_domain(Policy::DOMAIN_ALERT_ROUTING).first
    assert_equal 0, policy.policy_rules.count
  end

  test "create with alert_source_id creates a source-scoped policy" do
    source = @workspace.alert_sources.create!(name: "Northflank", provider: AlertSource::PROVIDER_NORTHFLANK)

    post policy_rules_url, params: {
      alert_source_id: source.id,
      rule: { conditions: [], outcome: { action: AlertIngestService::ACTION_DROP } }
    }

    policy = source.reload.alert_routing_policy
    assert policy.present?
    assert_equal 1, policy.policy_rules.count
    assert_redirected_to settings_alert_routing_path(source_id: source.id)
  end

  test "move_up swaps priorities" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    first = create_rule!(policy, 1)
    second = create_rule!(policy, 2)

    patch move_up_policy_rule_url(second)

    assert_equal 2, first.reload.priority
    assert_equal 1, second.reload.priority
  end

  test "update toggles enabled without touching conditions" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    rule = policy.policy_rules.create!(priority: 1,
      conditions: [ { field: "event", operator: PolicyRule::OPERATOR_CONTAINS, value: "crash" } ],
      outcome: { "action" => AlertIngestService::ACTION_DROP })

    patch policy_rule_url(rule), params: { rule: { enabled: false } }

    rule.reload
    assert_not rule.enabled
    assert_equal 1, rule.conditions.size
  end

  test "destroy removes the rule" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    rule = create_rule!(policy, 1)

    delete policy_rule_url(rule)

    assert_nil PolicyRule.find_by(id: rule.id)
  end

  test "cannot touch another workspace's rule" do
    other = workspaces(:slack_workspace_two)
    policy = other.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    rule = create_rule!(policy, 1)

    delete policy_rule_url(rule)

    assert_response :not_found
    assert PolicyRule.exists?(rule.id)
  end
end
