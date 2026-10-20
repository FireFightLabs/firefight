require "test_helper"
require Rails.root.join("db/migrate/20261020160000_sync_named_tools")

class SyncNamedToolsTest < ActiveSupport::TestCase
  test "an existing Cloudflare connection gets the named tools switched on, without asking its server, and keeps its own tools as they were" do
    workspace = workspaces(:slack_workspace_one)
    cloudflare = workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    notion = workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "notion", name: "Notion", slug: "notion",
                                            settings: { "server_url" => "https://mcp.notion.com/mcp" })
    execute = cloudflare.tools.create!(name: "execute", description: "Runs a script", read_only: false, enabled: false, params_schema: { "type" => "object" })
    Integrations::McpClient.expects(:new).never
    named = Integrations::Provider.for("cloudflare").named_tools.definitions.map(&:name)

    ActiveRecord::Migration.suppress_messages { SyncNamedTools.new.up }

    assert_equal named.sort, cloudflare.tools.where(name: named).pluck(:name).sort
    assert cloudflare.tools.where(name: named).all? { |tool| tool.enabled && !tool.read_only && tool.removed_at.nil? }
    assert_not execute.reload.enabled, "an admin's choice stays"
    assert_nil execute.removed_at, "the server's own tools are not taken for gone"
    assert_empty notion.tools, "a provider that adds none is left as it is"

    ActiveRecord::Migration.suppress_messages { SyncNamedTools.new.up }
    assert_equal named.size, cloudflare.tools.where(name: named).count, "running it again adds nothing"
  end
end
