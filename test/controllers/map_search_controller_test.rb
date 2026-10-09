require "test_helper"

class MapSearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    build_two_environment_map(@workspace)
    SearchDocument.index!(ResourceMap::Resource, ResourceMap::Resource.where(workspace: @workspace).pluck(:id))
    SearchDocument.index!(CatalogEntry, @workspace.catalog_entries.pluck(:id))
    sign_in(users(:bob), @workspace)
  end

  test "the search answers with what it is, why it matched and the page that opens it" do
    get map_search_url(q: "orders-db"), as: :json

    result = response.parsed_body["results"].first
    assert_equal [ "resource", "orders-db", "Exactly its name.", "database", "Northflank", "acme/shop", "Production" ],
                 result.values_at("type", "title", "why", "kind", "providerName", "account", "environment")
    assert_equal resource_map_path(view: ResourceMap::VIEW_FOCUS, resource: result["id"]), result["href"]
  end

  test "a member narrowed to Production finds only what runs there" do
    limit_map_to(@workspace, @member, catalog_entries(:production_env))

    get map_search_url(q: "db"), as: :json

    assert_equal [ "orders-db" ], response.parsed_body["results"].map { |result| result["title"] }
  end

  test "a catalog entry and a memory open where they live" do
    memory = Chat::Memory.create!(workspace: @workspace, text: "Authentication tokens live for an hour", state: Chat::Memory::STATE_CONFIRMED)

    get map_search_url(q: "authentication"), as: :json

    hrefs = response.parsed_body["results"].to_h { |result| [ result["type"], result["href"] ] }
    assert_equal catalogue_type_path("service", entry: catalog_entries(:auth_service).id), hrefs["catalog_entry"]
    assert_equal memory_path(memory: memory.id), hrefs["memory"]
  end

  test "a member who reads no part of the map is told why instead of finding nothing" do
    grant = limit_map_to(@workspace, @member, catalog_entries(:production_env))
    grant.update_column(:expires_at, 1.minute.ago)
    Ability::Resolver.bust!(principal_type: @member.class.polymorphic_name, principal_id: @member.id, workspace_id: @workspace.id)

    get map_search_url(q: "web"), as: :json

    assert_response :success
    assert_equal({ "results" => [], "refusal" => MapSearchController::NO_MAP_REACH }, response.parsed_body)
  end

  test "a search held for approval says so instead of failing" do
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })

    get map_search_url(q: "web"), as: :json

    assert_response :success
    approval = @workspace.ability_approvals.find_by!(action_key: Ability::Action::MAP_READ)
    assert_equal({ "results" => [], "refusal" => WebAuthorization.pending_message(approval) }, response.parsed_body)
  end
end
