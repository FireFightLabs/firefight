require "test_helper"

class Api::V1::SeveritiesControllerTest < ActionDispatch::IntegrationTest
  test "returns 401 without authorization header" do
    get api_v1_severities_url
    assert_response :unauthorized
    assert_equal "unauthorized", json_response["error"]["type"]
  end

  test "returns 401 with invalid token" do
    get api_v1_severities_url, headers: api_headers(token: "ff_invalid")
    assert_response :unauthorized
  end

  test "returns 403 without read permission on severities" do
    # Use a key that has no severities permission
    key_without_perm = api_keys(:inactive_key)
    key_without_perm.update_columns(active: true)
    key_without_perm.replace_permissions!({ "incidents" => [ "read" ] })
    token = "ff_test_inactive_token_123456789"
    ApiKey.authenticate(token) # clear cache by re-authenticating

    get api_v1_severities_url, headers: api_headers(token: token)
    assert_response :forbidden
  end

  test "lists severities for the workspace" do
    get api_v1_severities_url, headers: api_headers
    assert_response :success

    data = json_response
    assert data.key?("severities")
    assert data["severities"].is_a?(Array)
    assert data["severities"].length > 0

    severity = data["severities"].first
    assert severity.key?("id")
    assert severity.key?("name")
    assert severity.key?("slug")
    assert severity.key?("rank")
  end

  test "excludes soft-deleted severities" do
    severity = workspaces(:slack_workspace_one).incident_severities.first
    severity.update_column(:deleted_at, Time.current)

    get api_v1_severities_url, headers: api_headers
    assert_response :success

    ids = json_response["severities"].map { |s| s["id"] }
    assert_not_includes ids, severity.id
  end
end
