require "test_helper"

class Api::V1::IncidentTypesControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incident_types, :api_keys

  test "returns 401 without authorization" do
    get api_v1_incident_types_url
    assert_response :unauthorized
  end

  test "lists incident types" do
    get api_v1_incident_types_url, headers: api_headers
    assert_response :success

    data = json_response
    assert data.key?("incident_types")
    assert data["incident_types"].is_a?(Array)

    if data["incident_types"].any?
      incident_type = data["incident_types"].first
      assert incident_type.key?("id")
      assert incident_type.key?("name")
    end
  end
end
