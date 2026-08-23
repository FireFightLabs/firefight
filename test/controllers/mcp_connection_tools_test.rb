require "test_helper"

class McpConnectionToolsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog",
      settings: { "server_url" => "https://mcp.example/mcp" }
    )
    @tool = @integration.tools.create!(name: "logs_query", read_only: true, enabled: true)
  end

  test "a tool the provider no longer offers is not published over MCP" do
    @tool.update!(removed_at: Time.current)

    assert_empty Mcp::ConnectionToolFactory.tools_for(@workspace)
  end

  test "a denied call on a per-environment connection names the environments to pick from" do
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:development_env).id)

    hint = Mcp::ConnectionToolFactory.environment_hint(@tool)

    assert_includes hint, "Retry with environment set to one of:"
    assert_includes hint, catalog_entries(:production_env).slug
    assert_includes hint, catalog_entries(:development_env).slug
  end

  test "no hint when a global credential row resolves the call" do
    @integration.integration_environments.create!
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)

    assert_equal "", Mcp::ConnectionToolFactory.environment_hint(@tool)
  end

  test "no hint for a single wired environment" do
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)

    assert_equal "", Mcp::ConnectionToolFactory.environment_hint(@tool)
  end
end
