require "test_helper"

# A workspace without Slack refuses to declare from every entry point, with the same sentence, and creates nothing.
class IncidentsWaitForSlackTest < ActionDispatch::IntegrationTest
  REASON = "Connect Slack first to run incidents.".freeze

  setup do
    @membership = Workspace.sign_up!(name: "Quiet Co", user: users(:alice))
    @workspace = @membership.workspace
    @severity = @workspace.incident_severities.active.first
  end

  test "the public API answers 422 with the reason" do
    key, token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Pager", permissions: { "incidents" => %w[read create] }
    )

    assert_no_difference -> { Incident.count } do
      post api_v1_incidents_url, headers: api_headers(token: token),
        params: { idempotency_key: SecureRandom.uuid, name: "Checkout failing", severity_id: @severity.id }.to_json
    end

    assert_response :unprocessable_entity
    assert_equal "incidents_blocked", json_response.dig("error", "type")
    assert_equal REASON, json_response.dig("error", "message")
    assert key.persisted?
  end

  test "the MCP declare tool answers with the reason" do
    _, token = ApiKey.create_with_token!(workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Personal")

    post mcp_path,
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { name: Mcp::Tools::DECLARE_INCIDENT, arguments: { answers: { name: "Checkout failing", severity: @severity.slug } } } }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }

    result = JSON.parse(response.body).fetch("result")
    assert result["isError"]
    assert_equal REASON, result.dig("content", 0, "text")
    assert_equal 0, @workspace.incidents.count
  end

  # Every page with no id in its path, so a page that asks the platform for something shows up here.
  test "every dashboard page a new workspace opens renders without reaching for Slack" do
    sign_in(users(:alice), @workspace)

    paths = Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.delete_suffix("(.:format)")
      path if route.verb == "GET" && path.start_with?("/app") && path.exclude?(":") && path.exclude?("*")
    end

    assert_operator paths.size, :>, 20
    paths.uniq.each do |path|
      get path, headers: inertia_headers
      assert_operator response.status, :<, 500, "#{path} answered #{response.status}"
    end
  end
end
