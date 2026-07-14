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

  test "same name allowed across scopes, unique within a scope" do
    source = @workspace.alert_sources.create!(name: "Src", provider: AlertSource::PROVIDER_GENERIC)
    Policy.create!(workspace: @workspace, domain: Policy::DOMAIN_ALERT_ROUTING, name: "Alert routing")
    scoped = Policy.new(workspace: @workspace, domain: Policy::DOMAIN_ALERT_ROUTING, name: "Alert routing", scoped_to: source)
    assert scoped.valid?
    scoped.save!

    duplicate = Policy.new(workspace: @workspace, domain: Policy::DOMAIN_ALERT_ROUTING, name: "Alert routing", scoped_to: source)
    assert_not duplicate.valid?
  end

  test "scoped_to must belong to the same workspace" do
    other = workspaces(:slack_workspace_two)
    source = other.alert_sources.create!(name: "Theirs", provider: AlertSource::PROVIDER_GENERIC)

    policy = Policy.new(workspace: @workspace, domain: Policy::DOMAIN_ALERT_ROUTING, name: "X", scoped_to: source)
    assert_not policy.valid?
  end

  test "ordered_rules sorts by priority" do
    policy = Policy.create!(workspace: @workspace, domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    late = policy.policy_rules.create!(priority: 20, conditions: [], outcome: { "action" => PolicyRule::AlertRoutingOutcome::ACTION_DROP })
    early = policy.policy_rules.create!(priority: 10, conditions: [], outcome: { "action" => PolicyRule::AlertRoutingOutcome::ACTION_DROP })

    assert_equal [ early, late ], policy.ordered_rules.to_a
  end

  test "alert routing domain_config validates grouping knobs" do
    policy = Policy.new(workspace: workspaces(:slack_workspace_one), domain: Policy::DOMAIN_ALERT_ROUTING,
                        name: "Knobs", domain_config: { "grouping_window_minutes" => 2 })
    assert_not policy.valid?

    policy.domain_config = { "grouping_window_minutes" => 30, "content_match_fields" => [ "service" ] }
    assert policy.valid?

    policy.domain_config = { "content_match_fields" => "service" }
    assert_not policy.valid?
  end
end
