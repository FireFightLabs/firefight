require "test_helper"

class Integrations::Capabilities::NorthflankTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { api_token: "x" }.to_json)
    Integrations::Packs::Northflank.tool_definitions.each do |definition|
      integration.tools.create!(name: definition.name, description: definition.description, read_only: definition.read_only, enabled: true,
                                params_schema: definition.params_schema)
    end
    @web = resource!(ResourceMap::KIND_SERVICE, "web", "web")
    resource!(ResourceMap::KIND_DATABASE, "db", "db")
  end

  test "run history is a service's builds, and those of the build service it runs builds of" do
    history = resolve(Integrations::Capabilities::HISTORY, "resource" => "web", "limit" => 5)
    assert_equal "build_history", history.tool.name
    assert_equal({ "resource" => "web", "limit" => 5 }, history.arguments.slice("resource", "limit"))

    builder = resource!(ResourceMap::KIND_BUILD_SERVICE, "builder", "builder")
    ResourceMap::Link.create!(workspace: @workspace, from_resource: @web, to_resource: builder, relation: ResourceMap::RELATION_RUNS_BUILDS_OF,
                              integration_environment: @row, origin: ResourceMap::ORIGIN_DECLARED, last_seen_at: Time.current)
    assert_equal "builder", resolve(Integrations::Capabilities::HISTORY, "resource" => "web").arguments["resource"]
    assert_equal "builder", resolve(Integrations::Capabilities::HISTORY, "resource" => "builder").arguments["resource"]
    assert_match "no connection offers run history",
                 assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::HISTORY, "resource" => "db") }.message
  end

  test "every tool the adapter runs is one the pack declares, and build history is wrapped" do
    assert_empty Integrations::Capabilities::Northflank::TOOLS.values - Integrations::Packs::Northflank.tool_definitions.map(&:name)
    assert Integrations::Capabilities.wrapped?(@workspace.integrations.find_by!(slug: "northflank").tools.find_by!(name: "build_history"))
    assert_match "see how long its runs usually take", Integrations::Capabilities.halon_sentence("northflank", "Northflank")
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def resource!(kind, id, name)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: kind, external_id: id, name: name,
                                  integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end
end
