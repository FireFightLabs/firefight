require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @inviter   = workspace_memberships(:alice_workspace_one)
  end

  # validations

  test "requires email" do
    invitation = Invitation.new(workspace: @workspace, invited_by: @inviter)
    assert_not invitation.valid?
    assert_includes invitation.errors[:email], "can't be blank"
  end

  test "rejects invalid email format" do
    invitation = Invitation.new(workspace: @workspace, invited_by: @inviter, email: "not-an-email")
    assert_not invitation.valid?
    assert_includes invitation.errors[:email], "is invalid"
  end

  test "sets expiry to default 7 days from now on create" do
    invitation = Invitation.create!(workspace: @workspace, invited_by: @inviter, email: "new@example.com")
    assert_in_delta 7.days.from_now.to_f, invitation.expires_at.to_f, 5
  end

  test "rejects duplicate active invitations for same workspace + email" do
    Invitation.create!(workspace: @workspace, invited_by: @inviter, email: "dup@example.com")
    duplicate = Invitation.new(workspace: @workspace, invited_by: @inviter, email: "dup@example.com")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
  end

  test "allows new invitation after previous one is redeemed" do
    first = Invitation.create!(workspace: @workspace, invited_by: @inviter, email: "again@example.com")
    first.update!(redeemed_at: Time.current, redeemed_by: @inviter)

    second = Invitation.new(workspace: @workspace, invited_by: @inviter, email: "again@example.com")
    assert second.valid?
  end

  # scopes

  test "active scope excludes redeemed and expired" do
    pending = Invitation.create!(workspace: @workspace, invited_by: @inviter, email: "p@example.com")
    redeemed = Invitation.create!(workspace: @workspace, invited_by: @inviter, email: "r@example.com")
    redeemed.update!(redeemed_at: Time.current)
    expired = Invitation.create!(workspace: @workspace, invited_by: @inviter, email: "e@example.com", expires_at: 1.minute.ago)

    active_ids = Invitation.active.pluck(:id)
    assert_includes active_ids, pending.id
    assert_not_includes active_ids, redeemed.id
    assert_not_includes active_ids, expired.id
  end

  # consume!

  test "consume! creates membership and marks invite redeemed" do
    user = User.create!(email: "consume@example.com", name: "Consumer")
    auth = OmniAuth::AuthHash.new(uid: "U_CONSUME", extra: { raw_info: { "sub" => "U_CONSUME" } })
    invitation = Invitation.create!(workspace: @workspace, invited_by: @inviter, email: "consume@example.com")

    membership = invitation.consume!(user: user, auth_hash: auth)

    assert membership.persisted?
    assert_equal user.id, membership.user_id
    assert_equal @workspace.id, membership.workspace_id
    invitation.reload
    assert invitation.redeemed_at.present?
    assert_equal membership.id, invitation.redeemed_by_id
  end
end
