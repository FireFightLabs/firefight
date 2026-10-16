require "test_helper"

class WorkspaceMemberProvisionerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @adapter   = mock("adapter")
  end

  test "returns existing membership without asking the platform again" do
    existing = workspace_memberships(:alice_workspace_one)

    @adapter.stubs(:member_refusal).returns(nil)
    @adapter.expects(:get_user_info).never

    membership = WorkspaceMemberProvisioner.find_or_provision!(
      workspace: @workspace,
      platform_user_id: existing.platform_user_id,
      adapter: @adapter
    )

    assert_equal existing.id, membership.id
  end

  test "provisions a member via adapter.get_user_info when no membership exists" do
    @adapter.stubs(:member_refusal).returns(nil)
    @adapter.expects(:get_user_info).with(user_id: "U_ADAPTER_PATH").returns(
      {
        user_id: "U_ADAPTER_PATH",
        display_name: "Real Name",
        real_name: "Real Name",
        avatar_url: "https://example.com/avatar.jpg",
        email: "real@example.com",
        email_confirmed: true
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

  test "a sign-in's own profile names the person, and the platform is still asked whether they are a member (OIDC path)" do
    @adapter.stubs(:member_refusal).returns(nil)
    @adapter.expects(:get_user_info).with(user_id: "U_OIDC_PATH").returns({ real_name: "From Slack", email: "oidc@example.com", email_confirmed: true })

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
    @adapter.stubs(:member_refusal).returns(nil)
    @adapter.stubs(:get_user_info).returns({ real_name: "Racer", email: "racer@example.com", email_confirmed: true })

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
    @adapter.stubs(:member_refusal).returns(nil)
    @adapter.expects(:get_user_info).with(user_id: "U_EMAIL_JOINER").returns(
      { real_name: "Email Joiner", email: "Joined-By-Email@example.com", email_confirmed: true }
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

  test "an email the platform has not confirmed never reaches the person who holds it" do
    holder = User.create!(email: "unconfirmed@example.com", name: "Holder")
    @adapter.stubs(:member_refusal).returns(nil)
    @adapter.stubs(:get_user_info).with(user_id: "U_UNCONFIRMED").returns({ real_name: "Claimant", email: "unconfirmed@example.com", email_confirmed: false })

    membership = WorkspaceMemberProvisioner.find_or_provision!(workspace: @workspace, platform_user_id: "U_UNCONFIRMED", adapter: @adapter)

    assert_not_equal holder, membership.user
    assert_equal "Holder", holder.reload.name
    assert_not_equal "unconfirmed@example.com", membership.user.email
  end

  test "a guest or someone from another organisation is refused with the platform's sentence and given no seat" do
    profile = { real_name: "Guest", email: "guest@example.com", email_confirmed: true }
    @adapter.stubs(:get_user_info).with(user_id: "U_GUEST").returns(profile)
    @adapter.stubs(:member_refusal).with(profile: profile).returns("Guests of this Slack workspace can't use Firefight.")

    assert_no_difference -> { @workspace.workspace_memberships.count } do
      error = assert_raises(WorkspaceMemberProvisioner::Refused) do
        WorkspaceMemberProvisioner.admit!(workspace: @workspace, platform_user_id: "U_GUEST", adapter: @adapter)
      end
      assert_equal "Guests of this Slack workspace can't use Firefight.", error.message
      assert_nil WorkspaceMemberProvisioner.find_or_provision!(workspace: @workspace, platform_user_id: "U_GUEST", adapter: @adapter)
      assert_equal "Guests of this Slack workspace can't use Firefight.",
                   WorkspaceMemberProvisioner.refusal(workspace: @workspace, platform_user_id: "U_GUEST", adapter: @adapter)
    end
    assert_not User.exists?(email: "guest@example.com")
  end

  test "a member whose saved profile says they are a guest is asked about again, refused while they still are and let in once they are not" do
    seat = workspace_memberships(:alice_workspace_one)
    seat.update!(platform_data: { "raw" => { "is_restricted" => true } })
    stored = seat.platform_data
    @adapter.stubs(:member_refusal).with(profile: stored).returns("Guests can't.")
    @adapter.stubs(:get_user_info).with(user_id: seat.platform_user_id).returns({ raw: { is_restricted: true } }).then.returns({ raw: { is_restricted: false } })
    @adapter.stubs(:member_refusal).with(profile: { raw: { is_restricted: true } }).returns("Guests can't.")
    @adapter.stubs(:member_refusal).with(profile: { raw: { is_restricted: false } }).returns(nil)

    assert_raises(WorkspaceMemberProvisioner::Refused) do
      WorkspaceMemberProvisioner.admit!(workspace: @workspace, platform_user_id: seat.platform_user_id, adapter: @adapter)
    end
    assert_equal seat, WorkspaceMemberProvisioner.admit!(workspace: @workspace, platform_user_id: seat.platform_user_id, adapter: @adapter)
    assert_equal false, seat.reload.platform_data.dig("raw", "is_restricted"), "the refreshed profile is kept, so it is not asked again"
  end

  test "a member's platform id, once known, is never replaced by another account" do
    seat = workspace_memberships(:alice_workspace_one)

    seat.link_platform_user!("U_SECOND_ACCOUNT")

    assert_equal "U12345678", seat.reload.platform_user_id
  end
end
