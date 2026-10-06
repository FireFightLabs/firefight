require "test_helper"

class Integrations::Capabilities::TursoTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    turso = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "turso", name: "Turso", slug: "turso",
                                            settings: { "server_url" => "https://mcp.turso.ai/mcp" })
    @row = turso.integration_environments.create!
    @tool = turso.tools.create!(name: "get_database", description: "Database", read_only: true, enabled: true,
                                params_schema: { "type" => "object", "properties" => { "database" => { "type" => "string" } } })
    ResourceMap::Resource.create!(workspace: @workspace, provider: "turso", account: "default", kind: ResourceMap::KIND_DATABASE,
                                  external_id: "0eb771dd", name: "shop", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "status names the database by the parameter the connected tool reports" do
    call = Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::STATUS, { "resource" => "shop" }, principal: map_reader)

    assert_equal [ @row, "get_database", { "database" => "shop" } ], [ call.environment_row, call.tool.name, call.arguments ]
    assert_equal [ Integrations::Capabilities::STATUS ], Integrations::Capabilities::Turso.capabilities
  end

  test "a tool that takes the database some other way is refused in words, and its own tool stays offered" do
    @tool.update!(params_schema: { "type" => "object", "properties" => { "target" => {} } })

    error = assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::STATUS, { "resource" => "shop" }, principal: map_reader) }
    assert_match "ask it with Turso's own tool", error.message
    assert_not Integrations::Capabilities::Turso.wraps?("get_database")
  end
end
