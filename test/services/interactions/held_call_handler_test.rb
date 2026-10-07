require "test_helper"

class Interactions::HeldCallHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @conversation = @workspace.conversations.create!(kind: Conversation::KIND_CHANNEL, started_by: @bob, channel_id: "C9", thread_id: "5.5",
                                                     max_turns: 5, max_spend_cents: 100)
    approval = @workspace.ability_approvals.create!(
      principal: @bob, principal_label: "user:Bob Jones", action_key: "incidents.update", request_digest: "d", required_role: "admin",
      status: Ability::Approval::STATUS_APPROVED, approver: @alice, held_for_run: true, run_expires_at: 1.hour.from_now
    )
    @held = Chat::HeldCall.create!(chat: @conversation.chat_record, approval: approval, tool_name: "resolve_incident", status: Chat::HeldCall::STATUS_READY,
                                   message_channel_id: "C9", message_id: "5.6")
    @adapter = stub(update_held_call: { success: true })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    ConversationChannel.stubs(:broadcast_to)
  end

  test "Run in the thread hands the call to the chat's next turn as whoever pressed it" do
    assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, @bob.id, @held.id ]) do
      Interactions::HeldCallHandler.execute(press(Identifiers::HELD_CALL_RUN, @bob))
    end

    assert_equal [ Chat::HeldCall::STATUS_RUNNING, @bob ], [ @held.reload.status, @held.decided_by ]
  end

  test "Dismiss in the thread ends it, and a second press is told why only to whoever pressed it" do
    Interactions::HeldCallHandler.execute(press(Identifiers::HELD_CALL_DISMISS, @bob))
    assert_equal Chat::HeldCall::STATUS_DISMISSED, @held.reload.status

    @adapter.expects(:post_ephemeral).with(channel_id: "C9", user_id: @bob.platform_user_id, text: "This is no longer waiting to be run.")
    Interactions::HeldCallHandler.execute(press(Identifiers::HELD_CALL_RUN, @bob))
  end

  private

  def press(action_id, member)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: member.platform_user_id,
                    action_id: action_id, action_value: @held.id, channel_id: "C9")
  end
end
