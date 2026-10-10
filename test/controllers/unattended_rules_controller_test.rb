require "test_helper"

class UnattendedRulesControllerTest < ActionDispatch::IntegrationTest
  include OnCallTestHelper

  setup do
    alert_run_with_restart_fix
    sign_in(users(:alice), @workspace)
  end

  def rule_params(overrides = {})
    { capability: Integrations::Capabilities::RESTART, resource_id: @web.id, metric: "http_5xx", threshold: "50", minutes: "10" }.merge(overrides)
  end

  test "a rule is created by whoever set it and named in the notice" do
    post unattended_rules_url, params: { rule: rule_params }

    assert_redirected_to halon_on_call_path
    assert_equal "Unattended rule to restart web was created.", flash[:notice]
    rule = @workspace.unattended_rules.sole
    assert_equal [ @web, "http_5xx", 50, workspace_memberships(:alice_workspace_one) ], [ rule.resource, rule.metric, rule.threshold, rule.created_by ]
  end

  test "a resource on another workspace's map is refused" do
    other = ResourceMap::Resource.create!(workspace: workspaces(:slack_workspace_two), provider: "northflank", account: "x", kind: ResourceMap::KIND_SERVICE,
                                          external_id: "other", name: "other", first_seen_at: Time.current, last_seen_at: Time.current)

    post unattended_rules_url, params: { rule: rule_params(resource_id: other.id) }

    assert_empty @workspace.unattended_rules
  end

  test "editing, turning off and on say what changed" do
    rule = restart_rule

    patch unattended_rule_url(rule), params: { rule: rule_params(threshold: "75") }
    assert_equal "Unattended rule to restart web was updated.", flash[:notice]
    assert_equal 75, rule.reload.threshold

    patch unattended_rule_url(rule), params: { rule: { enabled: false } }
    assert_equal "Unattended rule to restart web is off.", flash[:notice]
    patch unattended_rule_url(rule), params: { rule: { enabled: true } }
    assert_equal "Unattended rule to restart web is on.", flash[:notice]
  end

  test "deleting asks the rule first, and one Halon acted under stays with the reason" do
    rule = restart_rule
    used = restart_rule(metric: "cpu")
    @plan.steps.sole.update!(applied_under_rule: used)

    delete unattended_rule_url(used)
    assert_equal used.reload.delete_blocked_reason, flash[:alert]

    delete unattended_rule_url(rule)
    assert_equal "Unattended rule to restart web was deleted.", flash[:notice]
    assert_not Ability::UnattendedRule.exists?(rule.id)
  end

  test "a member may not set what Halon does on its own" do
    sign_in(users(:bob), @workspace)

    post unattended_rules_url, params: { rule: rule_params }

    assert_empty @workspace.unattended_rules
  end
end
