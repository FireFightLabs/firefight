require "test_helper"

class Api::V1::CustomFieldsControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :api_keys, :ability_actions, :ability_grants,
           :incident_field_definitions, :incident_forms, :catalog_types

  test "lists active custom fields with schema" do
    get api_v1_custom_fields_url, headers: api_headers
    assert_response :success

    fields = json_response["custom_fields"]
    assert fields.is_a?(Array)
    assert fields.all? { |f| f.key?("slug") && f.key?("field_type") && f.key?("option_source") }
  end

  test "requires custom_fields:read permission" do
    get api_v1_custom_fields_url, headers: api_headers(token: "ff_test_read_only_token_12345678")
    assert_response :forbidden
  end

  test "requires authentication" do
    get api_v1_custom_fields_url
    assert_response :unauthorized
  end
end
