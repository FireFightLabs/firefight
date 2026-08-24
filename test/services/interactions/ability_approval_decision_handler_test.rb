require "test_helper"

class Interactions::AbilityApprovalDecisionHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @approval = Ability::Approval.create!(
      workspace: @workspace, principal: api_keys(:full_access_key),
      principal_label: api_keys(:full_access_key).principal_label,
      action_key: "catalog.delete", request_digest: Ability::Approval.digest("catalog.delete", {}, {}),
      required_role: WorkspaceMembership.roles[:admin],
      notification_channel_id: "C12345678", notification_message_id: "1234.5678"
    )
  end

  test "an admin click approves and updates the message" do
    stub_update_message

    result = Interactions::ApproveAbilityHandler.execute(build_interaction(@admin.platform_user_id))

    assert_nil result
    assert @approval.reload.approved?
    assert_equal @admin, @approval.approver
  end

  test "a deny click denies" do
    stub_update_message

    Interactions::DenyAbilityHandler.execute(build_interaction(@admin.platform_user_id))

    assert @approval.reload.denied?
  end

  test "a member without the required role gets an ephemeral rejection" do
    stub_post_ephemeral

    Interactions::ApproveAbilityHandler.execute(build_interaction(@member.platform_user_id))

    assert @approval.reload.pending?
  end

  test "unknown approval ids are ignored" do
    interaction = build_interaction(@admin.platform_user_id, value: SecureRandom.uuid)

    assert_nil Interactions::ApproveAbilityHandler.execute(interaction)
  end

  private

  def build_interaction(platform_user_id, value: @approval.id)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      channel_id: "C12345678",
      user_id: platform_user_id,
      action_id: Identifiers::APPROVE_ABILITY,
      action_value: value
    )
  end
end
