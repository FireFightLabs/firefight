require "test_helper"

# The kinds of thing the catalog holds, over REST. The API is the substrate
# every other surface is built on, so it carries the same writes the dashboard
# has rather than reading only.
class Api::V1::CatalogTypesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @key = api_keys(:full_access_key)
  end

  test "a type is created with the attributes its entries carry" do
    post api_v1_catalog_types_url,
         params: {
           name: "Datastore",
           attributes: [
             { name: "Engine", attribute_type: CatalogAttributeDefinition::TYPE_SELECT, options: %w[Postgres Redis] },
             { name: "Owning team", attribute_type: CatalogAttributeDefinition::TYPE_REFERENCE, reference_type: "team" }
           ]
         }, headers: api_headers, as: :json

    assert_response :created
    assert_equal "datastore", json_response["slug"]
    assert_equal [ "Engine", "Owning team" ], json_response["attribute_definitions"].map { |a| a["name"] }
    assert_equal "team", json_response["attribute_definitions"].last["reference_type"]
  end

  test "renaming never moves the slug" do
    post api_v1_catalog_types_url, params: { name: "Datastore" }, headers: api_headers, as: :json

    patch api_v1_catalog_type_url(slug: "datastore"),
          params: { name: "Data store" }, headers: api_headers, as: :json

    assert_response :success
    assert_equal "datastore", json_response["slug"]
    assert_equal "Data store", json_response["name"]
  end

  test "a built-in type cannot be deleted" do
    delete api_v1_catalog_type_url(slug: CatalogType::SYSTEM_KEY_SERVICE), headers: api_headers, as: :json

    assert_response :unprocessable_entity
    assert_match(/built-in/, json_response.dig("error", "message"))
    assert @workspace.catalog_types.active.exists?(slug: CatalogType::SYSTEM_KEY_SERVICE)
  end

  test "a type nothing points at is deleted" do
    post api_v1_catalog_types_url, params: { name: "Datastore" }, headers: api_headers, as: :json

    delete api_v1_catalog_type_url(slug: "datastore"), headers: api_headers, as: :json

    assert_response :no_content
    assert_not @workspace.catalog_types.active.exists?(slug: "datastore")
  end

  test "a key without catalog permission cannot create one" do
    _, token = create_service_key(
      workspace: @workspace, created_by: workspace_memberships(:alice_workspace_one), name: "Reader",
      permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read] }
    )

    post api_v1_catalog_types_url, params: { name: "Datastore" },
         headers: { "Authorization" => "Bearer #{token}" }, as: :json

    assert_response :forbidden
  end
end
