require "test_helper"

class Api::V1::RunbooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    _, @token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Personal"
    )

    @failover = @workspace.runbooks.create!(
      name: "Database failover", summary: "Promote the replica", content: "Full procedure"
    )
    @failover.runbook_steps.create!(title: "Pause writes", instruction: "Stop the writer", position: 1)
    @failover.runbook_steps.create!(title: "Promote replica", instruction: "Run failover", position: 2)

    @rollback = @workspace.runbooks.create!(name: "Deploy rollback", summary: "Revert the release")
  end

  test "returns 401 without authorization" do
    get api_v1_runbooks_url
    assert_response :unauthorized
  end

  test "lists active runbooks with steps but no content" do
    get api_v1_runbooks_url, headers: api_headers(token: @token)
    assert_response :success

    data = json_response
    slugs = data["runbooks"].map { |r| r["slug"] }
    assert_includes slugs, @failover.slug
    assert_includes slugs, @rollback.slug

    failover = data["runbooks"].find { |r| r["slug"] == @failover.slug }
    assert_equal [ "Pause writes", "Promote replica" ], failover["steps"].map { |s| s["title"] }
    assert_not failover.key?("content")
  end

  test "shows a runbook by slug with full content and steps" do
    get api_v1_runbook_url(@failover.slug), headers: api_headers(token: @token)
    assert_response :success

    runbook = json_response["runbook"]
    assert_equal @failover.slug, runbook["slug"]
    assert_equal "Full procedure", runbook["content"]
    assert_equal [ 1, 2 ], runbook["steps"].map { |s| s["position"] }
  end

  test "shows a runbook by id" do
    get api_v1_runbook_url(@failover.id), headers: api_headers(token: @token)
    assert_response :success
    assert_equal @failover.slug, json_response["runbook"]["slug"]
  end

  test "returns 404 for a soft-deleted runbook" do
    @rollback.update!(deleted_at: Time.current)

    get api_v1_runbook_url(@rollback.slug), headers: api_headers(token: @token)
    assert_response :not_found
  end

  test "returns 404 for an unknown slug" do
    get api_v1_runbook_url("does-not-exist"), headers: api_headers(token: @token)
    assert_response :not_found
  end

  test "returns 403 for a service key without runbooks read permission" do
    get api_v1_runbooks_url, headers: api_headers
    assert_response :forbidden
    assert_equal "forbidden", json_response["error"]["type"]
  end
end
