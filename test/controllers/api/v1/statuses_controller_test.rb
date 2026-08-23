require "test_helper"

class Api::V1::StatusesControllerTest < ActionDispatch::IntegrationTest
  test "returns 401 without authorization" do
    get api_v1_statuses_url
    assert_response :unauthorized
  end

  test "lists statuses with lifecycle_stage" do
    get api_v1_statuses_url, headers: api_headers
    assert_response :success

    data = json_response
    assert data.key?("statuses")
    assert data["statuses"].length > 0

    status = data["statuses"].first
    assert status.key?("id")
    assert status.key?("name")
    assert status.key?("slug")
    assert status.key?("lifecycle_stage")
    assert_includes %w[triage active closed canceled], status["lifecycle_stage"]
  end
end
