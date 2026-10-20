require "test_helper"
require Rails.root.join("db/migrate/20261020120500_add_tools_beside_remote_servers")

class AddToolsBesideRemoteServersTest < ActiveSupport::TestCase
  test "an existing Supabase connection gets Firefight's own tools without asking its server, keeping the tools its server listed" do
    connection = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "supabase", name: "Supabase", slug: "beside_sb",
                                                                       settings: { "server_url" => "https://mcp.supabase.com/mcp" })
    connection.integration_environments.create!
    kept = connection.tools.create!(name: "list_projects", description: "Projects", read_only: true, enabled: false, params_schema: { "type" => "object" })
    Integrations::McpClient.any_instance.expects(:tools_list).never

    ActiveRecord::Migration.suppress_messages { AddToolsBesideRemoteServers.new.up }

    health = connection.tools.find_by!(name: "get_project_health")
    assert health.enabled
    assert health.read_only
    assert_not connection.tools.exists?(name: "restart_project"), "a connection left read only is offered no change"
    assert_not kept.reload.enabled, "an admin's choice stays"
    assert_nil kept.removed_at, "a server's tool is not taken as gone"

    ActiveRecord::Migration.suppress_messages { AddToolsBesideRemoteServers.new.up }
    assert_equal 1, connection.tools.where(name: "get_project_health").count
  end
end
