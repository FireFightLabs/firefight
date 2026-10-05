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

  private

  def inertia_headers = { "X-Inertia" => "true", "X-Inertia-Version" => InertiaRails.configuration.version.to_s }

  def inertia_props(url)
    get url, headers: inertia_headers
    JSON.parse(response.body).fetch("props")
  end
end
