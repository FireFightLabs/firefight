require "test_helper"
require Rails.root.join("db/migrate/20261011200000_sync_release_pipeline_tools")

class SyncReleasePipelineToolsTest < ActiveSupport::TestCase
  test "existing AWS, Google Cloud and Kubernetes connections get the new reads and changes, and keep the tools they had as they were" do
    workspace = workspaces(:slack_workspace_one)
    added = {
      "aws" => %w[pipeline_executions codedeploy_deployments stack_events app_runner_operations beanstalk_events describe_app stop_service_deployment
                  stop_pipeline_execution rollback_pipeline_stage stop_codedeploy_deployment cancel_stack_update],
      "google_cloud" => %w[list_executions list_rollouts rollback_target cancel_rollout],
      "kubernetes" => %w[workload_runs rollout_pause rollout_resume run_cronjob_now suspend_cronjob resume_cronjob]
    }
    connections = added.keys.to_h do |provider|
      connection = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: provider.humanize, slug: "rp_#{provider}")
      [ provider, connection ]
    end
    kept = connections["aws"].tools.create!(name: "describe_resource", description: "Describe", read_only: true, enabled: false, params_schema: { "type" => "object" })

    ActiveRecord::Migration.suppress_messages { SyncReleasePipelineTools.new.up }

    added.each do |provider, names|
      tools = connections[provider].tools.where(name: names)
      assert_equal names.sort, tools.pluck(:name).sort, provider
      assert tools.all?(&:enabled), "#{provider}'s new tools arrive switched on"
    end
    assert connections["aws"].tools.find_by!(name: "pipeline_executions").read_only
    assert_not connections["aws"].tools.find_by!(name: "cancel_stack_update").read_only
    assert_not kept.reload.enabled, "an admin's choice stays"
  end
end
