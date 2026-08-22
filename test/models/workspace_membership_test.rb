require "test_helper"

class WorkspaceMembershipTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
  end

  test "resolve finds a member by membership id, platform user id, or email" do
    assert_equal @alice, @workspace.workspace_memberships.resolve(@alice.id)
    assert_equal @alice, @workspace.workspace_memberships.resolve(@alice.platform_user_id)
    assert_equal @alice, @workspace.workspace_memberships.resolve(@alice.email)
  end

  test "resolve matches an email whatever its case" do
    assert_equal @alice, @workspace.workspace_memberships.resolve(@alice.email.upcase)
  end

  test "resolve returns nil for a blank or unknown reference" do
    assert_nil @workspace.workspace_memberships.resolve(nil)
    assert_nil @workspace.workspace_memberships.resolve("")
    assert_nil @workspace.workspace_memberships.resolve("stranger@example.com")
    assert_nil @workspace.workspace_memberships.resolve("U00000000")
  end

  test "resolve stays inside the workspace it is called on" do
    other_workspace = workspaces(:slack_workspace_two)

    assert_nil other_workspace.workspace_memberships.resolve(@alice.id)
    assert_nil other_workspace.workspace_memberships.resolve(@alice.platform_user_id)
  end
end
