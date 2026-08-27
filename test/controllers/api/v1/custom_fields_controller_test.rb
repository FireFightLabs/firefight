require "test_helper"

class Api::V1::CustomFieldsControllerTest < ActionDispatch::IntegrationTest
  test "lists active custom fields with schema" do
    get api_v1_custom_fields_url, headers: api_headers
    assert_response :success

    fields = json_response["custom_fields"]
    assert fields.is_a?(Array)
    assert fields.all? { |f| f.key?("slug") && f.key?("field_type") && f.key?("option_source") }
  end

  test "a catalog-backed field lists its entries as options" do
    get api_v1_custom_fields_url, headers: api_headers
    assert_response :success

    field = json_response["custom_fields"].find { |row| row["slug"] == "affected_services" }
    assert_equal "catalog", field["option_source"]
    assert field.key?("catalog_type_id")
    labels = field["options"].map { |option| option["label"] }
    assert_includes labels, catalog_entries(:auth_service).name
  end

  test "a fixed-options field lists its enabled options in position order" do
    definition = incident_field_definitions(:customer_tier_ws1)
    incident_field_options(:customer_tier_free).update!(disabled_at: Time.current)

    get api_v1_custom_fields_url, headers: api_headers
    assert_response :success

    field = json_response["custom_fields"].find { |row| row["slug"] == definition.slug }
    assert_equal [ "Enterprise", "Pro" ], field["options"].map { |option| option["label"] }
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
