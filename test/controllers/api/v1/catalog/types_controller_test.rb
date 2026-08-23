require "test_helper"

class Api::V1::Catalog::TypesControllerTest < ActionDispatch::IntegrationTest
  test "lists active types with attribute schema" do
    get api_v1_catalog_types_path, headers: api_headers
    assert_response :success

    types = json_response["types"]
    service = types.find { |t| t["slug"] == "service" }
    assert service
    assert service["attribute_definitions"].any? { |a| a["slug"] == "tier" && a["attribute_type"] == "select" }
  end

  test "shows a type by slug" do
    get api_v1_catalog_type_path(slug: "service"), headers: api_headers
    assert_response :success
    assert_equal "service", json_response["slug"]
  end

  test "requires catalog:read" do
    get api_v1_catalog_types_path, headers: api_headers(token: "ff_test_read_only_token_12345678")
    assert_response :forbidden
  end
end
