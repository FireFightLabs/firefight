require "test_helper"

class ApprovalNotificationServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C0INCIDENTS")
    @admin = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @approval = Ability::Approval.create!(
      workspace: @workspace, principal: api_keys(:full_access_key),
      principal_label: api_keys(:full_access_key).principal_label,
      action_key: "catalog.delete", request_digest: Ability::Approval.digest("catalog.delete", {}, {}),
      required_role: WorkspaceMembership.roles[:admin]
    )
  end

  test "asks in the incidents channel by default and remembers the message" do
    Slack::Client.expects(:post_message).once
      .with { |args| args[:channel] == "C0INCIDENTS" }
      .returns({ ok: true, ts: "1.1", channel: "C0INCIDENTS" })

    ApprovalNotificationService.post!(@approval)

    assert_equal [ { "channel_id" => "C0INCIDENTS", "message_id" => "1.1" } ], @approval.reload.notifications
  end

  test "direct messages each named approver instead of the channel" do
    @approval.update!(approver_ids: [ @bob.id ], notify: PolicyRule::ApprovalOutcome::NOTIFY_DM)
    Slack::Client.expects(:post_message).once
      .with { |args| args[:channel] == @bob.platform_user_id }
      .returns({ ok: true, ts: "2.2", channel: "D0BOB" })

    ApprovalNotificationService.post!(@approval)

    assert_equal [ { "channel_id" => "D0BOB", "message_id" => "2.2" } ], @approval.reload.notifications
  end

  test "both asks in the channel and messages everyone holding the role" do
    @approval.update!(notify: PolicyRule::ApprovalOutcome::NOTIFY_BOTH)
    channels = []
    Slack::Client.stubs(:post_message).with { |args| channels << args[:channel] }.returns({ ok: true, ts: "3.3", channel: "X" })

    ApprovalNotificationService.post!(@approval)

    assert_equal [ "C0INCIDENTS", @admin.platform_user_id ].sort, channels.sort
    assert_equal 2, @approval.reload.notifications.size
  end

  test "a workspace without an incidents channel still messages approvers" do
    @workspace.update!(incidents_channel_id: nil)
    @approval.update!(notify: PolicyRule::ApprovalOutcome::NOTIFY_BOTH)
    Slack::Client.expects(:post_message).once.returns({ ok: true, ts: "4.4", channel: "D0ALICE" })

    ApprovalNotificationService.post!(@approval)

    assert_equal 1, @approval.reload.notifications.size
  end

  test "resolution rewrites every message that was posted" do
    @approval.update!(notifications: [
      { "channel_id" => "C0INCIDENTS", "message_id" => "1.1" }, { "channel_id" => "D0BOB", "message_id" => "2.2" }
    ])
    @approval.approve!(by: @admin)
    updated = []
    Slack::Client.stubs(:update_message).with { |args| updated << [ args[:channel], args[:ts] ] }.returns({ ok: true })

    ApprovalNotificationService.mark_resolved!(@approval)

    assert_equal [ [ "C0INCIDENTS", "1.1" ], [ "D0BOB", "2.2" ] ], updated
  end
end
