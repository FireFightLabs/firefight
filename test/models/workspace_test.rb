require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  fixtures :workspaces

  test "the truth" do
    assert true
  end

  test "slack workspace fixture loads correctly" do
    workspace = workspaces(:slack_workspace_one)
    assert_equal "slack", workspace.platform
    assert_equal "T12345678", workspace.platform_id
    assert_equal "Test Workspace One", workspace.name
  end

  test "validates uniqueness of platform_id scoped to platform" do
    workspace = workspaces(:slack_workspace_one)
    duplicate = Workspace.new(
      platform: workspace.platform,
      platform_id: workspace.platform_id,
      name: "Duplicate",
      installed_at: Time.current
    )

    refute duplicate.valid?
    assert_includes duplicate.errors[:platform_id], "has already been taken"
  end
end
