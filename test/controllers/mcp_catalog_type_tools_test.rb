require "test_helper"

# The kinds of thing the catalog holds, over MCP. Entries were already
# reachable, the shape they sit in was not.
class McpCatalogTypeToolsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    _, @token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Personal"
    )
  end

  test "a type is created with the attributes its entries carry" do
    content, is_error = call_tool(Mcp::Tools::UPSERT_CATALOG_TYPE, {
      name: "Datastore",
      attributes: [
        { name: "Engine", attribute_type: CatalogAttributeDefinition::TYPE_SELECT, options: %w[Postgres Redis] },
        { name: "Owning team", attribute_type: CatalogAttributeDefinition::TYPE_REFERENCE, reference_type: "team" }
      ]
    })

    assert_not is_error, content.inspect
    assert_equal "datastore", content["slug"]
    assert_equal CatalogType::KIND_CUSTOM, content["kind"]
    assert_equal [ "Engine", "Owning team" ], content["attributes"].map { |a| a["name"] }
    assert_equal "team", content["attributes"].last["reference_type"]
  end

  # The same rule the rest of the configuration tools follow, so a resend does
  # not orphan whatever the entries already hold.
  test "resending an attribute under a new name renames rather than replacing it" do
    call_tool(Mcp::Tools::UPSERT_CATALOG_TYPE, {
      name: "Datastore", attributes: [ { name: "Engine", attribute_type: CatalogAttributeDefinition::TYPE_TEXT } ]
    })
    definition = @workspace.catalog_types.find_by!(slug: "datastore").catalog_attribute_definitions.sole

    call_tool(Mcp::Tools::UPSERT_CATALOG_TYPE, {
      slug: "datastore", attributes: [ { name: "Engine", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, required: true } ]
    })

    assert_equal definition.id, @workspace.catalog_types.find_by!(slug: "datastore").catalog_attribute_definitions.sole.id
  end

  test "changing the description alone leaves the shape alone" do
    call_tool(Mcp::Tools::UPSERT_CATALOG_TYPE, {
      name: "Datastore", attributes: [ { name: "Engine", attribute_type: CatalogAttributeDefinition::TYPE_TEXT } ]
    })

    content, = call_tool(Mcp::Tools::UPSERT_CATALOG_TYPE, { slug: "datastore", description: "Where the data lives." })

    assert_equal [ "Engine" ], content["attributes"].map { |a| a["name"] }
  end

  test "a reference to a type that does not exist says which" do
    _, is_error, text = call_tool(Mcp::Tools::UPSERT_CATALOG_TYPE, {
      name: "Datastore",
      attributes: [ { name: "Owner", attribute_type: CatalogAttributeDefinition::TYPE_REFERENCE, reference_type: "squad" } ]
    })

    assert is_error
    assert_match(/squad/, text)
  end

  test "a built-in type cannot be removed" do
    _, is_error, text = call_tool(Mcp::Tools::DELETE_CATALOG_TYPE, { slug: CatalogType::SYSTEM_KEY_SERVICE })

    assert is_error
    assert_match(/built-in/, text)
    assert @workspace.catalog_types.active.exists?(slug: CatalogType::SYSTEM_KEY_SERVICE)
  end

  test "a type another type points at cannot be removed until it is unpointed" do
    call_tool(Mcp::Tools::UPSERT_CATALOG_TYPE, { name: "Datastore" })
    call_tool(Mcp::Tools::UPSERT_CATALOG_TYPE, {
      name: "Pipeline",
      attributes: [ { name: "Reads from", attribute_type: CatalogAttributeDefinition::TYPE_REFERENCE, reference_type: "datastore" } ]
    })

    _, is_error, text = call_tool(Mcp::Tools::DELETE_CATALOG_TYPE, { slug: "datastore" })

    assert is_error
    assert_match(/Reads from/, text)
  end

  test "a type nothing points at is removed with its entries" do
    call_tool(Mcp::Tools::UPSERT_CATALOG_TYPE, { name: "Datastore" })

    content, is_error = call_tool(Mcp::Tools::DELETE_CATALOG_TYPE, { slug: "datastore" })

    assert_not is_error, content.inspect
    assert_not @workspace.catalog_types.active.exists?(slug: "datastore")
  end

  private

  def call_tool(name, arguments = {})
    post mcp_path,
         params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@token}" }
    result = JSON.parse(response.body).fetch("result")
    [ result["structuredContent"] || {}, result["isError"], result.dig("content", 0, "text") ]
  end
end
