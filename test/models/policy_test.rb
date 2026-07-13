require "test_helper"

class PolicyTest < ActiveSupport::TestCase
  fixtures :workspaces

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "valid with a known domain" do
    policy = Policy.new(workspace: @workspace, domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    assert policy.valid?
  end

  test "rejects unknown domain" do
    policy = Policy.new(workspace: @workspace, domain: "escalation", name: "X")
    assert_not policy.valid?
  end

  test "name is unique per workspace and domain" do
    Policy.create!(workspace: @workspace, domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    duplicate = Policy.new(workspace: @workspace, domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    assert_not duplicate.valid?

    other_domain = Policy.new(workspace: @workspace, domain: Policy::DOMAIN_AUTO_INVESTIGATE, name: "Routing")
    assert other_domain.valid?
  end

  test "ordered_rules sorts by priority" do
    policy = Policy.create!(workspace: @workspace, domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    late = policy.policy_rules.create!(priority: 20, conditions: [], outcome: {})
    early = policy.policy_rules.create!(priority: 10, conditions: [], outcome: {})

    assert_equal [ early, late ], policy.ordered_rules.to_a
  end
end
