require "test_helper"
require Rails.root.join("db/migrate/20261020100100_sync_railway_change_tools")

class SyncRailwayChangeToolsTest < ActiveSupport::TestCase
  test "an existing Railway connection gets the cron runs and traces reads and the four deployment changes, and keeps the tools it had as they were" do
    railway = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "railway", name: "Railway", slug: "railway")
    railway.tools.create!(name: "list_deployments", description: "Deployments", read_only: true, enabled: false, params_schema: { "type" => "object" })

    ActiveRecord::Migration.suppress_messages { SyncRailwayChangeTools.new.up }

    reads = railway.tools.where(name: %w[cron_runs search_traces])
    assert_equal 2, reads.count
    assert(reads.all? { |tool| tool.enabled && tool.read_only })
    changes = railway.tools.where(name: %w[cancel_deployment stop_deployment redeploy_deployment approve_deployment])
    assert_equal 4, changes.count
    assert(changes.none?(&:read_only))
    assert_not railway.tools.find_by!(name: "list_deployments").enabled, "an admin's choice stays"
  end
end
