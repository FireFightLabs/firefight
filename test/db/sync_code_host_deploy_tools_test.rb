require "test_helper"
require Rails.root.join("db/migrate/20261020140000_sync_code_host_deploy_tools")

class SyncCodeHostDeployToolsTest < ActiveSupport::TestCase
  ADDED = {
    "github" => { reads: %w[list_environments], changes: %w[rerun_job redeploy] },
    "gitlab" => { reads: %w[list_environments list_releases release_lookup list_tags], changes: %w[retry_job play_job cancel_job redeploy approve_deployment stop_environment] },
    "bitbucket" => { reads: %w[step_test_reports list_tags], changes: %w[redeploy] }
  }.freeze

  test "existing GitHub, GitLab and Bitbucket connections get the new reads and changes switched on, and keep the tools they had as they were" do
    workspace = workspaces(:slack_workspace_one)
    connections = ADDED.keys.to_h do |provider|
      [ provider, workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: provider.humanize, slug: "ch_#{provider}") ]
    end
    connections["gitlab"].tools.create!(name: "cancel_pipeline", description: "Cancel", read_only: false, enabled: false, params_schema: { "type" => "object" })

    ActiveRecord::Migration.suppress_messages { SyncCodeHostDeployTools.new.up }

    ADDED.each do |provider, added|
      reads = connections[provider].tools.where(name: added[:reads])
      changes = connections[provider].tools.where(name: added[:changes])
      assert_equal [ added[:reads].sort, added[:changes].sort ], [ reads.pluck(:name).sort, changes.pluck(:name).sort ], provider
      assert (reads.to_a + changes.to_a).all?(&:enabled), "#{provider}'s new tools arrive switched on"
      assert reads.all?(&:read_only)
      assert changes.none?(&:read_only)
    end
    assert_not connections["gitlab"].tools.find_by!(name: "cancel_pipeline").enabled, "an admin's choice stays"
  end
end
