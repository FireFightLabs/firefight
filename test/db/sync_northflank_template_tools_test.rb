require "test_helper"
require Rails.root.join("db/migrate/20261012090001_sync_northflank_template_tools")

class SyncNorthflankTemplateToolsTest < ActiveSupport::TestCase
  test "an existing Northflank connection gets the template read and the two template changes, and keeps the tools it had as they were" do
    northflank = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    northflank.tools.create!(name: "workflow_runs", description: "Runs", read_only: true, enabled: false, params_schema: { "type" => "object" })

    ActiveRecord::Migration.suppress_messages { SyncNorthflankTemplateTools.new.up }

    assert northflank.tools.find_by!(name: "template_runs").then { |tool| tool.enabled && tool.read_only }
    changes = northflank.tools.where(name: %w[run_template abort_template_run])
    assert_equal 2, changes.count
    assert(changes.none?(&:read_only))
    assert_not northflank.tools.find_by!(name: "workflow_runs").enabled, "an admin's choice stays"
  end
end
