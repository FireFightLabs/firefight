require "test_helper"
require Rails.root.join("db/migrate/20261011160000_sync_northflank_release_tools")

class SyncNorthflankReleaseToolsTest < ActiveSupport::TestCase
  test "an existing Northflank connection gets the new reads, switched on and read only, and keeps the tools it had as they were" do
    northflank = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    northflank.tools.create!(name: "build_history", description: "Builds", read_only: true, enabled: false, params_schema: { "type" => "object" })

    ActiveRecord::Migration.suppress_messages { SyncNorthflankReleaseTools.new.up }

    added = northflank.tools.where(name: %w[workflow_runs release_flow_runs backup_history])
    assert_equal 3, added.count
    assert(added.all? { |tool| tool.enabled && tool.read_only })
    assert_not northflank.tools.find_by!(name: "build_history").enabled, "an admin's choice stays"
  end
end
