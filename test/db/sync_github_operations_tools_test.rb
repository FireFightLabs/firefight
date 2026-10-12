require "test_helper"
require Rails.root.join("db/migrate/20261012141500_sync_github_operations_tools")

class SyncGithubOperationsToolsTest < ActiveSupport::TestCase
  READS = %w[pending_deployments repository_access list_actions_variables list_artifacts read_artifact].freeze
  CHANGES = %w[update_release publish_release revert_pull_request review_pending_deployment clear_actions_cache].freeze

  test "an existing GitHub connection gets the new reads and changes switched on, and keeps the tools it had as they were" do
    github = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    github.tools.create!(name: "create_draft_release", description: "Draft", read_only: false, enabled: false, params_schema: { "type" => "object" })

    ActiveRecord::Migration.suppress_messages { SyncGithubOperationsTools.new.up }

    reads = github.tools.where(name: READS)
    changes = github.tools.where(name: CHANGES)
    assert_equal READS.size, reads.count
    assert_equal CHANGES.size, changes.count
    assert (reads.to_a + changes.to_a).all?(&:enabled)
    assert reads.all?(&:read_only)
    assert changes.none?(&:read_only)
    assert_not github.tools.find_by!(name: "create_draft_release").enabled, "an admin's choice stays"
  end
end
