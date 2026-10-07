require "test_helper"
require Rails.root.join("db/migrate/20261007234100_finish_checklist_for_connected_workspaces")

class FinishChecklistForConnectedWorkspacesTest < ActiveSupport::TestCase
  test "a workspace that went through the old onboarding is done, and one started without Slack still has setup to do" do
    connected = workspaces(:slack_workspace_one).create_onboarding!(installer: workspace_memberships(:alice_workspace_one))
    started = Workspace.sign_up!(name: "Started Co", user: User.create!(email: "started@example.com", name: "Stella Start")).workspace.onboarding

    ActiveRecord::Migration.suppress_messages { FinishChecklistForConnectedWorkspaces.new.migrate(:up) }

    assert connected.reload.checklist_completed_at
    assert_nil started.reload.checklist_completed_at
  end
end
