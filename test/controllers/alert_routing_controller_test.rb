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

  test "update writes grouping knobs into domain_config" do
    patch alert_routing_url, params: { policy: { grouping_window_minutes: 45, content_match_fields: [ "service", "environment" ] } }

    policy = @workspace.policies.for_domain(Policy::DOMAIN_ALERT_ROUTING).first
    assert_equal 45, policy.domain_config["grouping_window_minutes"]
    assert_equal [ "service", "environment" ], policy.domain_config["content_match_fields"]
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

  test "test sees the source's name and provider the way ingest does" do
    source = @workspace.alert_sources.create!(name: "Prod Northflank", provider: AlertSource::PROVIDER_NORTHFLANK)
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [ { field: "provider", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ AlertSource::PROVIDER_NORTHFLANK ] } ],
      outcome: { "action" => AlertIngestService::ACTION_AUTO_CREATE }
    )

    post alert_routing_test_url, params: { alert_source_id: source.id, fields: { service: "checkout" } }, as: :json
    assert_response :success
    assert JSON.parse(response.body)["matched"]

    post alert_routing_test_url, params: { fields: { service: "checkout" } }, as: :json
    assert_response :success
    assert_not JSON.parse(response.body)["matched"]
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

  test "send_test delivers a routing test message to the resolved target" do
    membership = workspace_memberships(:alice_workspace_one)
    create_notify_policy(membership)
    Slack::WorkspaceAdapter.any_instance.expects(:post_routing_test_message)
      .with(channel_id: membership.platform_user_id, description: regexp_matches(/matched rule 1/))
      .returns({ message_id: "123.456", channel_id: "D123" })

    post alert_routing_send_test_url, params: { fields: { service: "checkout" } }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["sent"]
    assert_equal "#{membership.user.name} (DM)", body["notify"]
  end

  test "send_test refuses when no rule with a notify target matches" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(priority: 1, conditions: [],
                                outcome: { "action" => AlertIngestService::ACTION_AUTO_CREATE })

    post alert_routing_send_test_url, params: { fields: { service: "checkout" } }, as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "notify target"
  end

  test "send_test surfaces delivery failures" do
    create_notify_policy(workspace_memberships(:alice_workspace_one))
    Slack::WorkspaceAdapter.any_instance.stubs(:post_routing_test_message)
      .raises(AdapterError::NotInChannel.new("not_in_channel"))

    post alert_routing_send_test_url, params: { fields: { service: "checkout" } }, as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "Delivery failed"
  end

  private

  def create_notify_policy(membership)
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [],
      outcome: {
        "action" => AlertIngestService::ACTION_NOTIFY_ONLY,
        "notify" => { "type" => PolicyRule::AlertRoutingOutcome::TARGET_MEMBER, "member_id" => membership.id }
      }
    )
    policy
  end
end
