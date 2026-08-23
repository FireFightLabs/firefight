require "test_helper"

# One suite for the whole rule, a suspended workspace is refused at every entry
# point. Slack commands answer with the suspension message, surfaces that
# cannot answer drop the request, and authenticated surfaces return 403.
class WorkspaceSuspensionTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incident_types, :incidents, :api_keys

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(
      suspended_at: Time.current,
      suspended_reason: Workspace::Suspension::SUSPENSION_PAYMENT_FAILED
    )
  end

  test "slack command answers with the suspension message and never dispatches" do
    CommandDispatcher.expects(:dispatch).never

    request_data = slack_command_request(team_id: @workspace.platform_id, user_id: "U12345678", text: "new")
    post api_v1_commands_url, params: request_data[:body], headers: request_data[:headers]

    assert_response :success
    assert_match(/payment issue/, response.body)
  end

  test "slack interaction is dropped without dispatching" do
    InteractionDispatcher.expects(:dispatch).never

    request_data = slack_interaction_request(team: { id: @workspace.platform_id })
    post api_v1_interactions_url, params: request_data[:body], headers: request_data[:headers]

    assert_response :success
  end

  test "slack event is dropped before any handler runs" do
    Events::ReactionAddedHandler.expects(:execute).never

    EventDispatcher.dispatch(Platforms::SLACK, {
      "team_id" => @workspace.platform_id,
      "event" => { "type" => Identifiers::EVENT_REACTION_ADDED }
    })
  end

  test "public API returns 403 with the message" do
    get api_v1_incidents_url, headers: api_headers

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "workspace_suspended", body.dig("error", "type")
  end

  test "mcp returns 403 with the message" do
    membership = workspace_memberships(:alice_workspace_one)
    _, token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: membership, on_behalf_of: membership, name: "Personal"
    )

    post mcp_path,
         params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }

    assert_response :forbidden
    assert_equal "workspace_suspended", JSON.parse(response.body)["error"]
  end

  test "alert ingest rejects with 403 and records the rejection" do
    source = AlertSource.create!(workspace: @workspace, name: "Grafana", provider: AlertSource::PROVIDER_GENERIC)

    post api_v1_alert_ingest_path(endpoint_path: source.endpoint_path),
         params: { "title" => "cpu high" }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{source.secret_token}" }

    assert_response :forbidden
    assert_match(/payment issue/, response.body)
  end

  test "dashboard renders the suspended page with 403" do
    sign_in(users(:alice), @workspace)

    get dashboard_url, headers: inertia_headers

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "errors/suspended", body["component"]
    assert_match(/payment issue/, body.dig("props", "message"))
  end

  test "logout still works while suspended" do
    sign_in(users(:alice), @workspace)

    delete logout_url

    assert_response :redirect
  end

  test "an unsuspended workspace is untouched" do
    @workspace.update!(suspended_at: nil, suspended_reason: nil)
    sign_in(users(:alice), @workspace)

    get dashboard_url, headers: inertia_headers

    assert_response :success
  end
end
