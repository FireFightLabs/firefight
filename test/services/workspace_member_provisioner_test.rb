require "test_helper"

class WorkspaceMemberProvisionerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @adapter   = mock("adapter")
  end

  test "returns existing membership without hitting the adapter" do
    existing = workspace_memberships(:alice_workspace_one)

    @adapter.expects(:get_user_info).never

    membership = WorkspaceMemberProvisioner.find_or_provision!(
      workspace: @workspace,
      platform_user_id: existing.platform_user_id,
      adapter: @adapter
    )

    assert_equal existing.id, membership.id
  end

  test "provisions a member via adapter.get_user_info when no membership exists" do
    @adapter.expects(:get_user_info).with(user_id: "U_ADAPTER_PATH").returns(
      {
        user_id: "U_ADAPTER_PATH",
        display_name: "Real Name",
        real_name: "Real Name",
        avatar_url: "https://example.com/avatar.jpg",
        email: "real@example.com"
      }
    )

    assert_difference -> { @workspace.workspace_memberships.count }, 1 do
      membership = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: @workspace,
        platform_user_id: "U_ADAPTER_PATH",
        adapter: @adapter
      )

      assert_equal "U_ADAPTER_PATH", membership.platform_user_id
      assert_equal "member", membership.role
      assert_equal "real@example.com", membership.user.email
      assert_equal "Real Name", membership.user.name
    end
  end

  test "skips adapter when user_profile is provided (OIDC path)" do
    @adapter.expects(:get_user_info).never

    profile = OmniAuth::AuthHash::InfoHash.new(
      name: "Skip Adapter",
      email: "oidc@example.com",
      image: "https://example.com/oidc.jpg"
    )

    assert_difference -> { @workspace.workspace_memberships.count }, 1 do
      membership = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: @workspace,
        platform_user_id: "U_OIDC_PATH",
        adapter: @adapter,
        user_profile: profile
      )

      assert_equal "oidc@example.com", membership.user.email
      assert_equal "Skip Adapter", membership.user.name
      assert_equal "U_OIDC_PATH", membership.platform_user_id
    end
  end

  test "concurrent provision returns existing row instead of raising on the unique index" do
    # A row created by a concurrent request after the existence check but before the insert.
    # Forcing the find_by to miss drives execution into create_or_find_by!, which must return this row.
    existing = WorkspaceMembership.create!(
      workspace: @workspace,
      user: User.create!(email: "already-racing@example.com", name: "Already Racing"),
      platform_user_id: "U_RACE",
      role: :member,
      joined_at: Time.current
    )

    @workspace.workspace_memberships.stubs(:find_by).returns(nil).then.returns(existing)
    @adapter.stubs(:get_user_info).returns({ real_name: "Racer", email: "racer@example.com" })

    membership = nil
    assert_no_difference -> { @workspace.workspace_memberships.where(platform_user_id: "U_RACE").count } do
      assert_nothing_raised do
        membership = WorkspaceMemberProvisioner.find_or_provision!(
          workspace: @workspace,
          platform_user_id: "U_RACE",
          adapter: @adapter
        )
      end
    end

    assert_equal "U_RACE", membership.platform_user_id
  end

  test "returns nil on AdapterError" do
    @adapter.expects(:get_user_info).raises(AdapterError.new("boom"))

    assert_no_difference -> { @workspace.workspace_memberships.count } do
      result = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: @workspace,
        platform_user_id: "U_ERROR",
        adapter: @adapter
      )

      assert_nil result
    end
  end

  test "a teammate who joined by email is matched by who they are and gains their platform id" do
    teammate = User.create!(email: "joined-by-email@example.com", name: "Email Joiner")
    seat = @workspace.workspace_memberships.create!(user: teammate, role: :member, joined_at: Time.current)
    @adapter.expects(:get_user_info).with(user_id: "U_EMAIL_JOINER").returns(
      { real_name: "Email Joiner", email: "Joined-By-Email@example.com" }
    )

    membership = assert_no_difference -> { @workspace.workspace_memberships.count } do
      WorkspaceMemberProvisioner.find_or_provision!(workspace: @workspace, platform_user_id: "U_EMAIL_JOINER", adapter: @adapter)
    end

    assert_equal seat, membership
    assert_equal "U_EMAIL_JOINER", seat.reload.platform_user_id
  end

  test "a known user passed in is matched before anyone is created" do
    teammate = User.create!(email: "known@example.com", name: "Known")
    seat = @workspace.workspace_memberships.create!(user: teammate, role: :member, joined_at: Time.current)
    @adapter.expects(:get_user_info).never

    membership = WorkspaceMemberProvisioner.find_or_provision!(
      workspace: @workspace, platform_user_id: "U_KNOWN", adapter: @adapter, user: teammate
    )

    assert_equal seat, membership
    assert_equal "U_KNOWN", seat.reload.platform_user_id
  end

  test "a member's platform id, once known, is never replaced by another account" do
    seat = workspace_memberships(:alice_workspace_one)

    seat.link_platform_user!("U_SECOND_ACCOUNT")

    assert_equal "U12345678", seat.reload.platform_user_id
  end
end
