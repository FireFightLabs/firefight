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
