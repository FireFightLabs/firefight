require "test_helper"
require Rails.root.join("db/migrate/20261020100000_sync_render_run_and_change_tools")

class SyncRenderRunAndChangeToolsTest < ActiveSupport::TestCase
  test "an existing Render connection gets the three run reads and the thirteen changes, and keeps the tools it had as they were" do
    render = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "render", name: "Render", slug: "render")
    render.tools.create!(name: "list_events", description: "Events", read_only: true, enabled: false, params_schema: { "type" => "object" })

    ActiveRecord::Migration.suppress_messages { SyncRenderRunAndChangeTools.new.up }

    reads = render.tools.where(name: %w[cron_runs job_runs task_runs])
    assert_equal 3, reads.count
    assert(reads.all? { |tool| tool.enabled && tool.read_only })
    changes = render.tools.where(name: %w[trigger_cron_run cancel_cron_run cancel_job run_job run_task cancel_task_run cancel_deploy trigger_deploy turn_off_autodeploy set_autodeploy set_autoscaling suspend_service resume_service])
    assert_equal 13, changes.count
    assert(changes.none?(&:read_only))
    assert_not render.tools.find_by!(name: "list_events").enabled, "an admin's choice stays"
  end
end
