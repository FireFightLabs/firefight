require "test_helper"

# A hosted build's entitlements backend can close a workspace. Every way in that answers a suspension answers this
# the same way, through Workspace#access_blocked.
class WorkspaceAccessTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @message = block_access!("This workspace has no active plan.")
  end

  test "an install someone runs themselves lets every workspace in" do
    Entitlements.reset_backend!

    assert_nil @workspace.access_blocked
    assert_nil Entitlements.next_step_path(@workspace)
  end

  test "a suspension comes first, with its own message" do
    @workspace.update!(suspended_at: Time.current, suspended_reason: Workspace::Suspension::SUSPENSION_MISUSE)

    assert_match(/misuse/, @workspace.access_blocked.message)
  end

  test "slack command answers with the message and never dispatches" do
    CommandDispatcher.expects(:dispatch).never

    request_data = slack_command_request(team_id: @workspace.platform_id, user_id: "U12345678", text: "new")
    post api_v1_commands_url, params: request_data[:body], headers: request_data[:headers]

    assert_response :success
    assert_match @message, response.body
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
    assert_equal @message, JSON.parse(response.body).dig("error", "message")
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
    assert_equal @message, JSON.parse(response.body)["message"]
  end

  test "alert ingest rejects with 403" do
    source = AlertSource.create!(workspace: @workspace, name: "Grafana", provider: AlertSource::PROVIDER_GENERIC)

    post api_v1_alert_ingest_path(endpoint_path: source.endpoint_path),
         params: { "title" => "cpu high" }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{source.secret_token}" }

    assert_response :forbidden
    assert_match @message, response.body
  end

  test "dashboard renders the blocked page with the message" do
    sign_in(users(:alice), @workspace)

    get dashboard_url, headers: inertia_headers

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "errors/suspended", body["component"]
    assert_equal @message, body.dig("props", "message")
  end

  test "dashboard sends the person to the page that lifts the block when the backend names one" do
    block_access!("Choose a plan to keep going.", path: "/app/billing")
    sign_in(users(:alice), @workspace)

    get dashboard_url

    assert_redirected_to "/app/billing"
  end
end
