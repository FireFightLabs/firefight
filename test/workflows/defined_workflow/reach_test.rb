require "test_helper"

# Two connections of the same provider, each holding its own web service. A step that reads one of them needs that
# connection's read pack only, as the run reaches only that connection. Seen on a real canvas, a Watch of one service
# asked for the read pack of every connection that could read a status.
class DefinedWorkflow::ReachTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @shop, @shop_row = connection!("Shop", "shop")
    @blog, @blog_row = connection!("Blog", "blog")
    resource!(@shop_row, "shop-web")
    resource!(@blog_row, "blog-web")
  end

  test "a read that names its resource needs only the read pack of the connection holding it" do
    needed = DefinedWorkflow::Reach.for_tool(@workspace, status_tool, { "resource" => "shop-web" })

    assert_equal [ read_pack(@shop).id ], needed.filter_map(&:role).map(&:id)
    assert_includes needed.filter_map(&:action).map(&:key), Ability::Action::MAP_READ
  end

  test "a read that names its connection needs only that connection's read pack" do
    needed = DefinedWorkflow::Reach.for_tool(@workspace, status_tool, { "resource" => "shop-web", "connection" => @shop.slug })

    assert_equal [ read_pack(@shop).id ], needed.filter_map(&:role).map(&:id)
  end

  test "a read whose resource the run fills in later may reach any connection that could answer it" do
    needed = DefinedWorkflow::Reach.for_tool(@workspace, status_tool, { "resource" => "{{inputs.service}}" })

    assert_equal [ read_pack(@blog).id, read_pack(@shop).id ].sort, needed.filter_map(&:role).map(&:id).sort
  end

  test "a watch step reaches only the connection of the resource it watches, and publishing grants just that" do
    watch = { "steps" => [ { "label" => "Rollout", "capability" => "status", "resource" => "shop-web", "done_when" => "running" } ] }

    needed = DefinedWorkflow::Steps::Watch.reach(watch, @workspace)

    assert_equal [ read_pack(@shop).id ], needed.filter_map(&:role).map(&:id)
  end

  test "a watch step that names its connection reaches only that connection" do
    watch = { "steps" => [ { "label" => "Rollout", "capability" => "status", "resource" => "shop-web", "connection" => @shop.slug, "done_when" => "running" } ] }

    needed = DefinedWorkflow::Steps::Watch.reach(watch, @workspace)

    assert_equal [ read_pack(@shop).id ], needed.filter_map(&:role).map(&:id)
  end

  private

  def status_tool = Integrations::Capabilities.spec(Integrations::Capabilities::STATUS).tool_name

  def read_pack(integration) = Ability::Role.find_by!(integration_id: integration.id, pack: Ability::Role::PACK_READ)

  def connection!(name, project)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: name)
    row = integration.integration_environments.create!(credentials: { token: "x" }.to_json)
    row.store_fields!("project" => project)
    integration.tools.create!(name: "describe_resource", description: "Describe a resource", read_only: true, enabled: true,
                              params_schema: { "type" => "object", "properties" => { "resource" => {} } })
    [ integration, row ]
  end

  def resource!(row, name)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/#{name}", kind: ResourceMap::KIND_SERVICE, external_id: name,
                                  name: name, integration_environment: row, first_seen_at: Time.current, last_seen_at: Time.current)
  end
end
