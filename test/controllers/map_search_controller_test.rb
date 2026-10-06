require "test_helper"

class MapSearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    build_two_environment_map(@workspace)
    SearchDocument.index!(ResourceMap::Resource, ResourceMap::Resource.where(workspace: @workspace).pluck(:id))
    SearchDocument.index!(CatalogEntry, @workspace.catalog_entries.pluck(:id))
    sign_in(users(:bob), @workspace)
  end

  test "the search answers with what it is, why it matched and the page that opens it" do
    get map_search_url(q: "orders-db"), as: :json

    result = response.parsed_body.first
    assert_equal [ "resource", "orders-db", "Exactly its name.", "database", "Northflank", "acme/shop", "Production" ],
                 result.values_at("type", "title", "why", "kind", "providerName", "account", "environment")
    assert_equal resource_map_path(view: ResourceMap::VIEW_FOCUS, resource: result["id"]), result["href"]
  end

  test "a member narrowed to Production finds only what runs there" do
    limit_map_to(@workspace, @member, catalog_entries(:production_env))

    get map_search_url(q: "db"), as: :json

    assert_equal [ "orders-db" ], response.parsed_body.map { |result| result["title"] }
  end

  test "a catalog entry and a memory open where they live" do
    memory = Chat::Memory.create!(workspace: @workspace, text: "Authentication tokens live for an hour", state: Chat::Memory::STATE_CONFIRMED)

    get map_search_url(q: "authentication"), as: :json

    hrefs = response.parsed_body.to_h { |result| [ result["type"], result["href"] ] }
    assert_equal catalogue_type_path("service", entry: catalog_entries(:auth_service).id), hrefs["catalog_entry"]
    assert_equal memory_path(memory: memory.id), hrefs["memory"]
  end
end
