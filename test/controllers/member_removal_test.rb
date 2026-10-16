require "test_helper"

# An admin removes a member from Settings, Members. Their tokens and connected agents stop at once, they reach the
# workspace no more from any surface, their history stays, and an admin can add them back.
class MemberRemovalTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    _, @bob_token = ApiKey.create_with_token!(workspace: @workspace, created_by: @bob, on_behalf_of: @bob, name: "Bob's laptop")
    application = Doorkeeper::Application.create!(name: "Claude Code", redirect_uri: "http://localhost:33418/callback")
    @oauth = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: @bob.id, scopes: "mcp:read", expires_in: 2.hours)
    sign_in(users(:alice), @workspace)
  end

  # Action Cable names a connection by its identifiers, sorted.
  def page_stream(user, workspace) = "action_cable/#{[ user.to_gid_param, workspace.id ].sort.join(':')}"

  test "the Members page says what removing someone takes away, and why a member cannot be removed" do
    get settings_members_url, headers: inertia_headers

    rows = inertia_props["members"].index_by { |row| row["name"] }
    assert_equal "You can't remove yourself. Ask another admin.", rows["Alice Smith"]["removalBlockedReason"]
    assert_nil rows["Bob Jones"]["removalBlockedReason"]
    assert_equal [ 1, 1 ], rows["Bob Jones"].values_at("personalTokenCount", "connectedAgentCount")
  end

  test "the owner count comes with the page's rows, so no row counts owners on its own" do
    owner = @workspace.workspace_memberships.find_by!(role: :owner)
    @workspace.workspace_memberships.where.not(id: owner.id).update_all(role: :member)

    counted = @workspace.workspace_memberships.with_access_counts.find(owner.id)

    assert_equal 1, counted.owner_count
    assert_no_queries { counted.owner_count }
  end

  test "removing a member revokes their tokens and connected agents, cuts their live pages, keeps their history and says so" do
    assert_broadcasts(page_stream(users(:bob), @workspace), 1) do
      assert_no_broadcasts(page_stream(users(:bob), workspaces(:slack_workspace_two))) do
        delete workspace_membership_url(@bob)
      end
    end

    assert_redirected_to settings_members_path
    assert_equal "Bob Jones was removed from Test Workspace One.", flash[:notice]
    @bob.reload
    assert @bob.removed?
    assert_nil ApiKey.authenticate(@bob_token)
    assert @oauth.reload.revoked?
    assert_not @workspace.workspace_memberships.exists?(id: @bob.id), "no longer listed among the workspace's members"
    assert_not users(:bob).workspaces.include?(@workspace), "their session can no longer reach the workspace"
    assert WorkspaceMembership.exists?(@bob.id), "the row stays, so incidents and history keep naming them"
  end

  test "whatever a removed member left running is refused at the gateway" do
    MembershipRemoval.remove!(@bob, by: @alice)

    assert_raises(AbilityGateway::Denied) do
      AbilityGateway.authorize!(principal: @bob.reload, action_key: "incidents.read", workspace: @workspace) { :ran }
    end
  end

  test "Slack never adds a removed member back on its own, and tells them why" do
    MembershipRemoval.remove!(@bob, by: @alice)

    error = assert_raises(WorkspaceMemberProvisioner::Refused) do
      WorkspaceMemberProvisioner.admit!(workspace: @workspace, platform_user_id: @bob.platform_user_id, adapter: @workspace.adapter)
    end
    assert_equal WorkspaceMembership::REMOVED_REFUSAL, error.message
    assert_equal 2, WorkspaceMembership.where(workspace: @workspace).count, "no second seat is made for them"
  end

  test "an admin adds a removed member back from the Members page, and an invitation they accept adds them back too" do
    MembershipRemoval.remove!(@bob, by: @alice)

    get settings_members_url, headers: inertia_headers
    assert_equal [ "Bob Jones" ], inertia_props["removedMembers"].map { |row| row["name"] }

    post restore_workspace_membership_url(@bob)
    assert_equal "Bob Jones was added back to Test Workspace One.", flash[:notice]
    assert_not @bob.reload.removed?

    MembershipRemoval.remove!(@bob, by: @alice)
    invitation = @workspace.invitations.create!(email: users(:bob).email, invited_by: @alice, last_sent_at: Time.current)
    assert_equal @bob, invitation.accept!(users(:bob))
    assert_not @bob.reload.removed?
  end

  test "an admin cannot remove themselves, and a member cannot remove anyone" do
    delete workspace_membership_url(@alice)
    assert_equal "You can't remove yourself. Ask another admin.", flash[:alert]
    assert_not @alice.reload.removed?

    sign_in(users(:bob), @workspace)
    delete workspace_membership_url(@alice), headers: { "HTTP_REFERER" => settings_members_url }
    assert_match "You don't have permission", flash[:alert]
    assert_not @alice.reload.removed?
  end

  test "a removal whose revoking fails leaves the member in place, so the next try revokes everything" do
    ApiKey.any_instance.stubs(:soft_delete!).raises(ActiveRecord::StatementInvalid)

    assert_raises(ActiveRecord::StatementInvalid) { MembershipRemoval.remove!(@bob, by: workspace_memberships(:alice_workspace_one)) }
    assert_not @bob.reload.removed?
  end
end
