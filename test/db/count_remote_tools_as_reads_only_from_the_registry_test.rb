require "test_helper"
require Rails.root.join("db/migrate/20261016170000_count_remote_tools_as_reads_only_from_the_registry")

class CountRemoteToolsAsReadsOnlyFromTheRegistryTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @sentry = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry", settings: { "server_url" => "https://mcp.sentry.dev/mcp" })
    @custom = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "custom_mcp", name: "Ours", settings: { "server_url" => "https://tools.acme.example/mcp" })
  end

  test "a tool its server called a read becomes a change unless the registry lists it, keeping whether it is on and an admin's mark" do
    listed = tool(@sentry, "search_issues", enabled: true)
    claimed = tool(@sentry, "update_issue", enabled: false)
    marked = tool(@custom, "status", enabled: true, marked: true)
    unmarked = tool(@custom, "drop_everything", enabled: true)

    migrate

    assert listed.reload.read_only?
    assert_not claimed.reload.read_only?
    assert_not claimed.enabled?, "a tool switched off stays off"
    assert marked.reload.read_only?, "an admin's mark is kept"
    assert_not unmarked.reload.read_only?
    assert_not unmarked.declared_read?
    assert_equal Ability::Action::RISK_WRITE, unmarked.ability_action.reload.risk_level
    assert_includes @custom.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES).actions, unmarked.ability_action
  end

  private

  def tool(integration, name, enabled:, marked: false)
    integration.tools.create!(name: name, read_only: true, enabled: enabled, marked_read: marked,
                              spec: { "tool_name" => name, Integration::Tool::DECLARED_READ => !marked })
  end

  def migrate = ActiveRecord::Migration.suppress_messages { CountRemoteToolsAsReadsOnlyFromTheRegistry.new.migrate(:up) }
end
