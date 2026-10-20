require "test_helper"
require Rails.root.join("db/migrate/20261020170200_add_database_tools_beside_their_servers")

class AddDatabaseToolsBesideTheirServersTest < ActiveSupport::TestCase
  test "an existing ClickHouse connection gets scale_service as a change, asks no server, and keeps the tools its server listed" do
    connection = connect("clickhouse", "https://mcp.clickhouse.cloud/mcp")
    kept = connection.tools.create!(name: "get_services_list", description: "Services", read_only: true, enabled: false, params_schema: { "type" => "object" })
    Integrations::McpClient.any_instance.expects(:tools_list).never

    migrate

    tool = connection.tools.find_by!(name: "scale_service")
    assert tool.enabled
    assert_not tool.read_only
    assert tool.spec[Integrations::Provider::FIREFIGHT_TOOL]
    assert_equal "Sets a ClickHouse Cloud service's replicas, memory per replica or idle scaling.", tool.summary
    assert connection.tools.find_by!(name: "activities").read_only, "a tool beside the server that only reads arrives as a read"
    assert_not kept.reload.enabled, "an admin's choice stays"
    assert_nil kept.removed_at, "a server's tool is not taken as gone"

    migrate
    assert_equal 1, connection.tools.where(name: "scale_service").count
  end

  test "existing Neon, Turso and Upstash connections get their tools beside the server, asking no server" do
    neon = connect("neon", "https://mcp.neon.tech/mcp")
    turso = connect("turso", "https://mcp.turso.ai/mcp")
    upstash = connect("upstash", "https://mcp.upstash.com/mcp")
    Integrations::McpClient.any_instance.expects(:tools_list).never

    migrate

    assert_not neon.tools.find_by!(name: "restore_branch").read_only
    assert neon.tools.find_by!(name: "consumption_history").read_only
    assert turso.tools.find_by!(name: "database_usage").read_only
    assert_not upstash.tools.find_by!(name: "restore_redis_backup").read_only
  end

  private

  def connect(provider, server_url)
    connection = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: provider, name: provider.capitalize,
                                                                       slug: "beside_#{provider}", settings: { "server_url" => server_url })
    connection.integration_environments.create!
    connection
  end

  def migrate = ActiveRecord::Migration.suppress_messages { AddDatabaseToolsBesideTheirServers.new.up }
end
