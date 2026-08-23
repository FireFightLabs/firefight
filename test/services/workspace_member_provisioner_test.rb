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
    # Row created by a concurrent request after our existence check but before
    # our insert. Forcing the top-level find_by to miss drives execution into
    # create_or_find_by!, which must resolve the conflict to the existing row.
    existing = WorkspaceMembership.create!(
      workspace: @workspace,
      user: users(:alice),
      platform_user_id: "U_RACE",
      role: :member,
      joined_at: Time.current
    )

    # Top-level existence check misses (the row was created concurrently after
    # it ran). The rescue's re-query then finds the winner's row.
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
end
