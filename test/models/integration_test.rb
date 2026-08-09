require "test_helper"

class IntegrationTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :catalog_types, :catalog_entries

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @integration = Integration.create!(
      workspace: @workspace, kind: Integration::KIND_MCP, provider: "newrelic",
      name: "New Relic", settings: { "server_url" => "https://mcp.newrelic.example/mcp" }
    )
  end

  test "slug derives from the name and is immutable" do
    assert_equal "new_relic", @integration.slug

    @integration.slug = "renamed"
    assert_not @integration.valid?
  end

  test "executor is selected by kind and unimplemented kinds raise" do
    assert_equal Integrations::McpExecutor, @integration.executor
    assert_equal Integrations::NativeExecutor, Integration.new(kind: Integration::KIND_NATIVE).executor

    assert_raises(Integrations::Error) { Integration.new(kind: Integration::KIND_HTTP).executor }
  end

  test "second instance of a provider mints distinct action keys" do
    eu = Integration.create!(workspace: @workspace, kind: Integration::KIND_MCP, provider: "newrelic",
                             name: "New Relic EU", settings: { "server_url" => "https://eu.example/mcp" })

    us_tool = @integration.tools.create!(name: "logs.query", enabled: true)
    eu_tool = eu.tools.create!(name: "logs.query", enabled: true)

    assert_equal "new_relic.logs.query", us_tool.action_key
    assert_equal "new_relic_eu.logs.query", eu_tool.action_key
  end

  test "enabling a tool mints a tool-kind action with risk from read_only" do
    tool = @integration.tools.create!(name: "logs.query", read_only: true, enabled: true)

    action = Ability::Action.find_by!(workspace: @workspace, key: "new_relic.logs.query")
    assert_equal Ability::Action::KIND_TOOL, action.kind
    assert_equal Ability::Action::RISK_READ, action.risk_level
    assert action.reversible
    assert_equal tool, action.source

    writer = @integration.tools.create!(name: "dashboards.write", enabled: true)
    write_action = writer.ability_action
    assert_equal Ability::Action::RISK_WRITE, write_action.risk_level
    assert_not write_action.reversible
  end

  test "resolve_environment derives, never asserts" do
    prod = catalog_entries(:platform_team)
    prod_row = @integration.integration_environments.create!(catalog_entry_id: prod.id)

    assert_equal prod_row, @integration.resolve_environment(prod.id)
    assert_nil @integration.resolve_environment(SecureRandom.uuid)
    assert_equal prod_row, @integration.resolve_environment(nil), "single wired env is unambiguous"

    global = Integration.create!(workspace: @workspace, kind: Integration::KIND_MCP, provider: "github",
                                 name: "GitHub", settings: { "server_url" => "https://gh.example/mcp" })
    global_row = global.integration_environments.create!(catalog_entry_id: nil)
    assert_equal global_row, global.resolve_environment(nil)
  end
end
