require "test_helper"

class IntegrationTest < ActiveSupport::TestCase
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

  # Seen in a real chat. Halon named production on a connection with one environment and was told only that it was unknown.
  test "an unknown environment is refused naming the ones the connection has" do
    @integration.integration_environments.create!(catalog_entry_id: nil)
    assert_refused_with "Unknown environment 'staging'. This connection has one environment, so leave environment out.", "staging"

    @integration.integration_environments.destroy_all
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:development_env).id)
    assert_refused_with "Unknown environment 'staging'. This connection has: production, development.", "staging"

    @integration.integration_environments.create!(catalog_entry_id: nil)
    assert_refused_with "Unknown environment 'staging'. This connection has: production, development, or leave environment out for its default.", "staging"
  end

  test "the environment argument names the connection's environments, never one it does not have" do
    tool = @integration.tools.create!(name: "logs.query", enabled: true)
    @integration.integration_environments.create!(catalog_entry_id: nil)
    assert_equal "Leave this out. This connection has one environment.", environment_argument(tool)["description"]

    @integration.integration_environments.destroy_all
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:development_env).id)
    assert_equal "Environment slug, one of: production, development.", environment_argument(tool)["description"]
    assert_equal %w[production development], environment_argument(tool)["enum"]

    @integration.integration_environments.create!(catalog_entry_id: nil)
    assert_equal "Environment slug, one of: production, development. Leave it out for the connection's default.", environment_argument(tool)["description"]
  end

  test "no connection can be called all, since all asks every connection at once" do
    integration = workspaces(:slack_workspace_one).integrations.new(kind: Integration::KIND_MCP, provider: "custom", name: "All", slug: Integration::SLUG_ALL)

    assert_not integration.valid?
    assert_includes integration.errors[:slug], "is kept for asking every connection at once"
    assert_match "Pick a different name", Integration.name_blocked_reason("All")
    assert_nil Integration.name_blocked_reason("Datadog")
  end

  test "a name whose tools Halon would call by another connection's tool's name is refused when connecting" do
    workspace = workspaces(:slack_workspace_one)
    first = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Acme")
    first.tools.create!(name: "api_request", params_schema: { "type" => "object" })
    first.tools.create!(name: "prod_api_request", params_schema: { "type" => "object" })

    reason = Integration.name_blocked_reason("Acme prod", workspace: workspace, provider: "northflank")

    assert_equal "Acme prod would give its api_request tool the name acme_prod_api_request, which Acme (Northflank)'s prod_api_request " \
                 "tool already has, so Halon could not tell them apart. Pick a different name.", reason
    assert_nil Integration.name_blocked_reason("Acme eu", workspace: workspace, provider: "northflank")
    assert_nil Integration.name_blocked_reason("Acme prod", workspace: workspace, provider: "datadog"), "a provider with other tools does not collide"
  end

  test "a tool discovered later under another connection's tool's name cannot be switched on, alone or with the rest" do
    workspace = workspaces(:slack_workspace_one)
    first = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Acme")
    first.tools.create!(name: "prod_logs", enabled: true, params_schema: { "type" => "object" })
    second = workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "custom_mcp", name: "Acme prod", settings: { "server_url" => "https://x.example/mcp" })
    clash = second.tools.create!(name: "logs", params_schema: { "type" => "object" })
    second.tools.create!(name: "traces", params_schema: { "type" => "object" })

    assert_equal "Halon would call this tool acme_prod_logs, the name Acme (Northflank)'s prod_logs tool already has. Connect this account " \
                 "again under another name to switch it on.", clash.toggle_blocked_reason
    second.reload.set_all_tools!(true)
    assert_equal({ "logs" => false, "traces" => true }, second.tools.reload.to_h { |tool| [ tool.name, tool.enabled ] })
  end

  test "an action key names its connection the way a person tells it apart, and a system action names none" do
    workspace = workspaces(:slack_workspace_one)
    faylee = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    faylee.tools.create!(name: "api_request", params_schema: { "type" => "object" })

    assert_equal({ "faylee.api_request" => "Faylee (Northflank)" }, Integration.display_names_for(workspace.id, %w[faylee.api_request incidents.create]))
  end

  test "a connection already called all before the name was kept still saves" do
    integration = workspaces(:slack_workspace_one).integrations.new(kind: Integration::KIND_MCP, provider: "custom", name: "All", slug: Integration::SLUG_ALL)
    integration.save!(validate: false)

    assert integration.update(name: "All of it")
  end

  private

  def assert_refused_with(words, slug)
    refusal = assert_raises(Integration::UnknownEnvironment) { @integration.reload.environment_entry_for(slug) }
    assert_equal words, refusal.message
  end

  def environment_argument(tool) = tool.reload.offered_schema.dig("properties", Integration::Tool::ENVIRONMENT_ARG)
end
