require "test_helper"

class ResourceMap::VisibilityTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    build_two_environment_map(@workspace)
  end

  test "a member reads the whole map without a grant, and so does an admin" do
    all = %w[dev-worker orders-db secret-db shop.example.com web]

    assert_equal all, visible_names(@member)
    assert_equal all, visible_names(@admin)
    assert_nil ResourceMap::Resource.environments_visible_to(@member, @workspace)
  end

  test "a grant limits a member to its environments, and a resource only an unscoped connection reports is outside them" do
    limit_map_to(@workspace, @member, catalog_entries(:production_env))

    assert_equal %w[orders-db web], visible_names(@member)
    assert_equal [ catalog_entries(:production_env).id ], ResourceMap::Resource.environments_visible_to(@member, @workspace)
  end

  test "a grant through a permission set limits a member the same way" do
    set = @workspace.ability_roles.create!(name: "Production map", slug: "production_map")
    set.role_actions.create!(action: Ability::Action.system!(Ability::Action::MAP_READ))
    Ability::Grant.grant!(workspace: @workspace, principal: @member, target: { role: set }, environment_ids: [ catalog_entries(:development_env).id ])

    assert_equal %w[dev-worker secret-db], visible_names(@member)
  end

  test "an admin keeps the whole map whatever they were granted" do
    limit_map_to(@workspace, @admin, catalog_entries(:production_env))

    assert_includes visible_names(@admin), "secret-db"
  end

  test "an expired grant leaves a member nothing rather than handing the whole map back" do
    grant = limit_map_to(@workspace, @member, catalog_entries(:production_env))
    grant.update_column(:expires_at, 1.minute.ago)
    Ability::Resolver.bust!(principal_type: @member.class.polymorphic_name, principal_id: @member.id, workspace_id: @workspace.id)

    assert_empty visible_names(@member)
    assert_not @member.may?(Ability::Action::RESOURCE_MAP, Ability::Action::ACTION_READ, @workspace)
  end

  test "a resource another connection also reports is read in that connection's environment too" do
    ResourceMap.record!(@production_row, ResourceMap::Snapshot.new(resources: [ map_found("web"), map_found("orders-db", ResourceMap::KIND_DATABASE),
                                                                                map_found("secret-db", ResourceMap::KIND_DATABASE) ], links: [], gaps: []))
    limit_map_to(@workspace, @member, catalog_entries(:production_env))

    assert_includes visible_names(@member), "secret-db"
  end

  test "the investigator reads the whole map through the grant every workspace gives it, and a key with no grant reads none of it" do
    assert_equal 5, ResourceMap::Resource.visible_to(SystemAgent.investigator, @workspace).count
    assert_empty ResourceMap::Resource.visible_to(api_keys(:read_only_key), @workspace)
  end

  test "a neighborhood within what a reader sees leaves out a link to a resource outside it and counts it" do
    limit_map_to(@workspace, @member, catalog_entries(:production_env))
    visible = ResourceMap::Resource.visible_to(@member, @workspace)
    web = map_resource(@workspace, "web")

    sentences = web.neighborhood(within: visible).map { |link, _hop| link.sentence }

    assert_equal [ "web uses orders-db" ], sentences
    assert_equal 1, web.links_out_of_reach(visible)
    assert_equal 3, web.neighborhood.size
  end

  test "a member narrowed to some environments still opens the map, which a scope-less call admits" do
    limit_map_to(@workspace, @member, catalog_entries(:production_env))

    assert @member.may?(Ability::Action::RESOURCE_MAP, Ability::Action::ACTION_READ, @workspace)
    assert AbilityGateway.reach(principal: @member, action_key: Ability::Action::MAP_READ, workspace: @workspace)
  end

  test "the query layer composes with what a limited reader sees, and never reaches past it" do
    limit_map_to(@workspace, @member, catalog_entries(:production_env))
    visible = ResourceMap::Resource.visible_to(@member, @workspace)
    web = map_resource(@workspace, "web")
    database = map_resource(@workspace, "orders-db")

    assert_equal %w[orders-db web], ResourceMap::Query.new(@workspace, within: visible).scope.order(:name).pluck(:name)
    assert_equal %w[orders-db], ResourceMap::Graph.new(web, direction: ResourceMap::Graph::DEPENDS_ON, within: visible).nodes.map { |node| node.resource.name }
    assert_equal %w[web], ResourceMap::BlastRadius.new(database, within: visible).dependents.pluck(:name)
    stats = ResourceMap::Stats.new(@workspace, within: visible)
    assert_equal 2, stats.total
    assert_equal [ @production_row ], stats.connections.map(&:environment_row)
    assert_equal({ ResourceMap::Change::KIND_APPEARED => 2 }, stats.recent_changes)
    assert_equal 5, ResourceMap::Stats.new(@workspace, within: ResourceMap::Resource.visible_to(SystemAgent.investigator, @workspace)).total
  end

  private

  def visible_names(principal) = ResourceMap::Resource.visible_to(principal, @workspace).order(:name).pluck(:name)
end
