require "test_helper"

class AlertRoutingControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  test "update creates the policy on first use and toggles enabled" do
    patch alert_routing_url, params: { policy: { enabled: false } }

    policy = @workspace.policies.for_domain(Policy::DOMAIN_ALERT_ROUTING).first
    assert policy.present?
    assert_not policy.enabled
  end

  test "test evaluates fields against the policy with a trace" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "checkout" ] } ],
      outcome: { "action" => AlertIngestService::ACTION_AUTO_CREATE }
    )

    post alert_routing_test_url, params: { fields: { service: "checkout", title: "504s" } }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["matched"]
    assert_equal AlertIngestService::ACTION_AUTO_CREATE, body.dig("outcome", "action")
    assert_equal 1, body["trace"].size
  end

  test "test resolves notify targets to readable labels" do
    membership = workspace_memberships(:alice_workspace_one)
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [],
      outcome: {
        "action" => AlertIngestService::ACTION_NOTIFY_ONLY,
        "notify" => { "type" => PolicyRule::AlertRoutingOutcome::TARGET_MEMBER, "member_id" => membership.id }
      }
    )

    post alert_routing_test_url, params: { fields: { service: "checkout" } }, as: :json

    assert_response :success
    assert_equal "#{membership.user.name} (DM)", JSON.parse(response.body).dig("resolution", "notify")
  end

  test "test labels channel notify targets with the channel name" do
    Slack::WorkspaceAdapter.any_instance.stubs(:list_channels).returns([ { id: "C123", name: "incidents" } ])
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [],
      outcome: {
        "action" => AlertIngestService::ACTION_NOTIFY_ONLY,
        "notify" => { "type" => PolicyRule::AlertRoutingOutcome::TARGET_CHANNEL, "channel_id" => "C123" }
      }
    )

    post alert_routing_test_url, params: { fields: { service: "checkout" } }, as: :json

    assert_response :success
    assert_equal "#incidents", JSON.parse(response.body).dig("resolution", "notify")
  end

  test "test without a policy returns 422" do
    post alert_routing_test_url, params: { fields: { service: "x" } }, as: :json

    assert_response :unprocessable_entity
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
