require "test_helper"

class AlertRouterTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @source = @workspace.alert_sources.create!(name: "Prod Northflank", provider: AlertSource::PROVIDER_NORTHFLANK)
  end

  test "routes through the scope's effective policy with the scope's fields" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [ { field: "provider", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ AlertSource::PROVIDER_NORTHFLANK ] } ],
      outcome: { "action" => AlertIngestService::ACTION_AUTO_CREATE }
    )

    routed = Alert::Router.new(@workspace, @source).route({ "service" => "checkout" })

    assert routed.matched?
    assert_equal policy, routed.policy
    assert_equal AlertSource::PROVIDER_NORTHFLANK, routed.fields["provider"], "the source adds its provider"
    assert_equal 1, routed.matched_rule.priority
    assert routed.trace.is_a?(Array)

    assert_not Alert::Router.new(@workspace, @workspace).route({ "service" => "checkout" }).matched?,
               "the workspace scope exposes no provider field"
  end

  test "enriches the context from the catalog before evaluating" do
    routed = Alert::Router.new(@workspace, @workspace).tap do
      @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    end.route({ "service" => catalog_entries(:auth_service).slug })

    assert_equal catalog_entries(:platform_team).slug, routed.context["team"]
  end

  test "returns nil when the scope has no enabled policy" do
    assert_nil Alert::Router.new(@workspace, @source).route({ "service" => "checkout" })

    disabled = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing", enabled: false)
    assert_not disabled.enabled?
    assert_nil Alert::Router.new(@workspace, @workspace).route({ "service" => "checkout" })
  end
end
