require "test_helper"

class ApprovalNotificationServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  test "a change Halon asked for in a chat asks its approvers directly and never the shared incidents channel" do
    @approval.update!(source: AbilityGateway::SOURCE_CONVERSATION, approver_ids: [ @bob.id ])
    channels = []
    Slack::Client.stubs(:post_message).with { |args| channels << args[:channel] }.returns({ ok: true, ts: "5.5", channel: "D0BOB" })

    ApprovalNotificationService.post!(@approval)

    assert_equal [ @bob.platform_user_id ], channels
  end

  test "a chat's change nobody can be asked directly about is asked in the channel rather than nowhere" do
    @approval.update!(source: AbilityGateway::SOURCE_CONVERSATION)
    WorkspaceMembership.where(workspace: @workspace).update_all(platform_user_id: nil)
    Slack::Client.expects(:post_message).once.with { |args| args[:channel] == "C0INCIDENTS" }.returns({ ok: true, ts: "6.6", channel: "C0INCIDENTS" })

    ApprovalNotificationService.post!(@approval)
  end

  test "the request says in plain words who wants to do what, with the call itself under Details" do
    blocks = Slack::Messages::Approval.build_request(@approval, shown: ApprovalNotificationService.shown(@approval), rich: true)

    card = blocks.sole
    assert_equal ":raised_hand:  #{@approval.principal_label} wants to: delete catalogue", card.dig(:title, :text)
    assert_equal "Needs a workspace admin", card.dig(:body, :text)
    assert_equal [ Identifiers::APPROVE_ABILITY, Identifiers::DENY_ABILITY, Identifiers::APPROVAL_DETAILS ], card[:actions].map { |button| button[:action_id] }
    assert_not_includes blocks.to_json, "catalog.delete"
  end

  test "once approved the request says who approved it, then how the call it let through went" do
    @approval.approve!(by: @admin)
    resolved = ->(approval) { Slack::Messages::Approval.build_resolved(approval, shown: ApprovalNotificationService.shown(approval), rich: true).sole }
    assert_equal "Approved by *#{@admin.display_name}*", resolved.call(@approval).dig(:body, :text)

    ran = Ability::Invocation.create!(workspace: @workspace, principal: api_keys(:full_access_key), principal_label: "key", action_key: "catalog.delete",
                                      idempotency_key: SecureRandom.uuid, decision: Ability::Invocation::DECISION_ALLOW, approval: @approval)
    assert_equal "Approved by *#{@admin.display_name}*  ·  working…", resolved.call(@approval).dig(:body, :text)

    ran.finalize!(outcome: Ability::Invocation::OUTCOME_SUCCESS)
    done = resolved.call(@approval)
    assert_equal [ ":white_check_mark:  #{@approval.principal_label} wants to: delete catalogue", "Approved by *#{@admin.display_name}*  ·  Done" ],
                 [ done.dig(:title, :text), done.dig(:body, :text) ]

    ran.update_columns(outcome: Ability::Invocation::OUTCOME_ERROR, error_summary: "The entry is still in use")
    failed = resolved.call(@approval)
    assert_equal [ ":x:  #{@approval.principal_label} wants to: delete catalogue", "Approved by *#{@admin.display_name}*  ·  Failed: The entry is still in use" ],
                 [ failed.dig(:title, :text), failed.dig(:body, :text) ]
  end

  test "a call an approval let through redraws the messages that asked once it ends" do
    @approval.approve!(by: @admin)
    @approval.update!(notifications: [ { "channel_id" => "D0BOB", "message_id" => "2.2" } ])
    Slack::Client.expects(:update_message).with { |args| args[:ts] == "2.2" && args[:blocks].to_json.include?("Done") }.returns({ ok: true })
    invocation = Ability::Invocation.create!(workspace: @workspace, principal: api_keys(:full_access_key), principal_label: "key", action_key: "catalog.delete",
                                             idempotency_key: SecureRandom.uuid, decision: Ability::Invocation::DECISION_ALLOW, approval: @approval)

    perform_enqueued_jobs(only: ApprovalOutcomeJob) { AbilityGateway::Authorization.new(invocation).finalize_success! }
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
