require "test_helper"

class PolicyRuleAlertRoutingOutcomeTest < ActiveSupport::TestCase
  fixtures :workspaces

  setup do
    @policy = Policy.create!(workspace: workspaces(:slack_workspace_one),
                             domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
  end

  def rule(outcome)
    @policy.policy_rules.build(priority: 1, conditions: [], outcome: outcome)
  end

  test "valid create outcome with owning-team invite" do
    assert rule({
      "action" => PolicyRule::AlertRoutingOutcome::ACTION_AUTO_CREATE,
      "invite" => [ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM, "of" => "service" }, { "type" => PolicyRule::AlertRoutingOutcome::TARGET_MEMBER, "member_id" => SecureRandom.uuid } ]
    }).valid?
  end

  test "valid notify outcome" do
    assert rule({
      "action" => PolicyRule::AlertRoutingOutcome::ACTION_NOTIFY_ONLY,
      "notify" => { "type" => PolicyRule::AlertRoutingOutcome::TARGET_CHANNEL, "channel_id" => "C1" }
    }).valid?
  end

  test "rejects unknown action" do
    r = rule({ "action" => "page_everyone" })
    assert_not r.valid?
    assert_includes r.errors[:outcome].join, "unknown action"
  end

  test "rejects notify on incident-creating actions" do
    r = rule({
      "action" => PolicyRule::AlertRoutingOutcome::ACTION_AUTO_CREATE,
      "notify" => { "type" => PolicyRule::AlertRoutingOutcome::TARGET_CHANNEL, "channel_id" => "C1" }
    })
    assert_not r.valid?
  end

  test "rejects invite on notify_only" do
    r = rule({
      "action" => PolicyRule::AlertRoutingOutcome::ACTION_NOTIFY_ONLY,
      "invite" => [ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_MEMBER, "member_id" => SecureRandom.uuid } ]
    })
    assert_not r.valid?
  end

  test "rejects targets missing their required key" do
    r = rule({
      "action" => PolicyRule::AlertRoutingOutcome::ACTION_NOTIFY_ONLY,
      "notify" => { "type" => PolicyRule::AlertRoutingOutcome::TARGET_CHANNEL }
    })
    assert_not r.valid?
    assert_includes r.errors[:outcome].join, "requires channel_id"
  end

  test "team targets require entry_id" do
    r = rule({
      "action" => PolicyRule::AlertRoutingOutcome::ACTION_AUTO_CREATE,
      "invite" => [ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_TEAM } ]
    })
    assert_not r.valid?
    assert_includes r.errors[:outcome].join, "requires entry_id"
  end

  test "rejects channel targets in invite" do
    r = rule({
      "action" => PolicyRule::AlertRoutingOutcome::ACTION_AUTO_CREATE,
      "invite" => [ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_CHANNEL, "channel_id" => "C1" } ]
    })
    assert_not r.valid?
  end

  test "non-alert-routing domains accept any outcome shape" do
    policy = Policy.create!(workspace: workspaces(:slack_workspace_one),
                            domain: Policy::DOMAIN_AUTO_INVESTIGATE, name: "AI")
    assert policy.policy_rules.build(priority: 1, conditions: [], outcome: { "whatever" => true }).valid?
  end
end
