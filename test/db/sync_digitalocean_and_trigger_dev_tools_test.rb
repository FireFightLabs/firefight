require "test_helper"
require Rails.root.join("db/migrate/20261020143000_sync_digitalocean_and_trigger_dev_tools")

class SyncDigitaloceanAndTriggerDevToolsTest < ActiveSupport::TestCase
  DIGITALOCEAN = %w[app_events cancel_deployment cancel_job_run cancel_autoscaling redeploy_app commit_rollback revert_rollback].freeze
  TRIGGER_DEV = %w[deploy_history cancel_run replay_run bulk_cancel_runs bulk_replay_runs abort_bulk_action pause_queue resume_queue override_queue_concurrency
                   reset_queue_concurrency pause_concurrency_limit resume_concurrency_limit override_concurrency_limit reset_concurrency_limit
                   resolve_error ignore_error unresolve_error].freeze

  test "existing DigitalOcean and Trigger.dev connections get the new tools, and keep the ones they had as they were" do
    workspace = workspaces(:slack_workspace_one)
    digitalocean = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "digitalocean", name: "DigitalOcean", slug: "digitalocean")
    trigger = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "trigger_dev", name: "Trigger.dev", slug: "trigger")
    digitalocean.tools.create!(name: "rollback_app", description: "Rollback", read_only: false, enabled: false, params_schema: { "type" => "object" })

    ActiveRecord::Migration.suppress_messages { SyncDigitaloceanAndTriggerDevTools.new.up }

    assert_equal DIGITALOCEAN.sort, digitalocean.tools.where(name: DIGITALOCEAN).pluck(:name).sort
    assert_equal TRIGGER_DEV.sort, trigger.tools.where(name: TRIGGER_DEV).pluck(:name).sort
    assert digitalocean.tools.find_by!(name: "app_events").read_only
    assert_not trigger.tools.find_by!(name: "cancel_run").read_only
    assert_not digitalocean.tools.find_by!(name: "rollback_app").enabled, "an admin's choice stays"
  end
end
