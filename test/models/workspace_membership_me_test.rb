require "test_helper"

# "me" is whoever is acting, so a person can say make me the lead without being asked for their own email.
class WorkspaceMembershipMeTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
  end

  test "me resolves to the person acting" do
    assert_equal @alice, @workspace.workspace_memberships.resolve!("me", acting: @alice)
    assert_equal @alice, @workspace.workspace_memberships.resolve!("Me", acting: @alice)
  end

  test "me means nobody when a machine is acting, since a key has no seat in an incident" do
    error = assert_raises(ActiveRecord::RecordNotFound) do
      @workspace.workspace_memberships.resolve!("me", acting: api_keys(:full_access_key))
    end

    assert_match "not a person", error.message
  end

  test "an email and an id still resolve as before, with or without someone acting" do
    assert_equal @alice, @workspace.workspace_memberships.resolve!(@alice.user.email, acting: @alice)
    assert_equal @alice, @workspace.workspace_memberships.resolve!(@alice.id)
  end
end
