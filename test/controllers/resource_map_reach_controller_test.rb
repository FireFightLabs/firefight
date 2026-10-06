require "test_helper"

class ResourceMapReachControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    build_two_environment_map(@workspace)
  end

  test "a member opens the map and sees every environment without a grant" do
    sign_in(users(:bob), @workspace)

    props = inertia_props(resource_map_path)

    assert_equal %w[dev-worker orders-db secret-db shop.example.com web], props["resources"].map { |resource| resource["name"] }.sort
    assert_nil props["readsIn"]
  end

  test "a member limited to Production sees only what runs there, its links and its connection, and is told so" do
    limit_map_to(@workspace, @member, catalog_entries(:production_env))
    sign_in(users(:bob), @workspace)

    props = inertia_props(resource_map_path)

    assert_equal %w[orders-db web], props["resources"].map { |resource| resource["name"] }.sort
    names = props["resources"].to_h { |resource| [ resource["id"], resource["name"] ] }
    assert_equal [ [ "web", "orders-db" ] ], props["links"].map { |link| [ names[link["fromId"]], names[link["toId"]] ] }
    assert_equal [ [ "Jobs could not be read in Production" ] ], props["connections"].map { |connection| connection["gaps"] }
    assert_equal [ "Production" ], props["readsIn"]
    TwoEnvironmentMapHelper::HIDDEN_NAMES.each { |name| assert_not_includes response.body, name }
  end

  test "an admin sees the whole map whatever they were granted" do
    limit_map_to(@workspace, workspace_memberships(:alice_workspace_one), catalog_entries(:production_env))
    sign_in(users(:alice), @workspace)

    assert_equal 5, inertia_props(resource_map_path)["resources"].size
  end

  test "the Memory page offers only the resources a limited member reads" do
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    limit_map_to(@workspace, @member, catalog_entries(:production_env))
    sign_in(users(:bob), @workspace)

    get memory_path, headers: inertia_headers
    labels = JSON.parse(response.body).dig("props", "subjects").map { |subject| subject["label"] }

    assert_includes labels, "web · Northflank"
    TwoEnvironmentMapHelper::HIDDEN_NAMES.each { |name| assert(labels.none? { |label| label.start_with?(name) }) }
  end

  test "a limited member's writes find only what they read, so a hidden resource or link answers as missing" do
    limit_map_to(@workspace, @member, catalog_entries(:production_env))
    Ability::Grant.grant!(workspace: @workspace, principal: @member, target: { action: Ability::Action.system!(Ability::Action.system_key(Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_UPDATE)) })
    hidden = map_resource(@workspace, "secret-db")
    suggestion = ResourceMap::Link.suggest!(from: map_resource(@workspace, "dev-worker"), to: hidden, relation: ResourceMap::RELATION_RUNS_BUILDS_OF, note: "seen in logs")
    entry_link = ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: hidden)
    sign_in(users(:bob), @workspace)

    post resource_map_links_path, params: { from_id: map_resource(@workspace, "web").id, to_id: hidden.id, relation: ResourceMap::RELATION_USES }
    assert_response :not_found
    post confirm_resource_map_link_path(suggestion)
    assert_response :not_found
    post dismiss_resource_map_link_path(suggestion)
    assert_response :not_found
    post resource_map_resource_entries_path(hidden), params: { catalog_entry_id: catalog_entries(:auth_service).id }
    assert_response :not_found
    delete resource_map_resource_entry_path(hidden, catalog_entries(:auth_service))
    assert_response :not_found

    assert_nil suggestion.reload.confirmed_at
    assert_nil suggestion.dismissed_at
    assert ResourceMap::EntryLink.exists?(entry_link.id)
    assert_not ResourceMap::Link.exists?(from_resource: map_resource(@workspace, "web"), to_resource: hidden)
  end

  test "the Memory page leaves out a hidden resource's memories, and confirming one finds nothing" do
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    limit_map_to(@workspace, @member, catalog_entries(:production_env))
    hidden = Chat::Memory.create!(workspace: @workspace, text: "secret-db holds the card tokens", subject: map_resource(@workspace, "secret-db"),
                                   state: Chat::Memory::STATE_UNCONFIRMED)
    sign_in(users(:bob), @workspace)

    get memory_path, headers: inertia_headers
    assert_not_includes response.body, "card tokens"

    post confirm_memory_path(hidden)
    assert_response :not_found
    assert_equal Chat::Memory::STATE_UNCONFIRMED, hidden.reload.state

    post memory_memories_path, params: { text: "secret-db is in Frankfurt", subject: Chat::Memory.subject_key(map_resource(@workspace, "secret-db")) }
    assert_response :not_found
  end

  private

  def inertia_headers = { "X-Inertia" => "true", "X-Inertia-Version" => InertiaRails.configuration.version.to_s }

  def inertia_props(url)
    get url, headers: inertia_headers
    JSON.parse(response.body).fetch("props")
  end
end
