require "test_helper"
require Rails.root.join("db/migrate/20261017100500_move_unwritten_undos_to_the_chat")

class MoveUnwrittenUndosToTheChatTest < ActiveSupport::TestCase
  test "a change still waiting for a model to write its undo is put back in the chat instead, and every other is untouched" do
    workspace = workspaces(:slack_workspace_one)
    alice = workspace_memberships(:alice_workspace_one)
    chat = Conversation.start_personal!(workspace: workspace, member: alice).chat_record
    made = lambda do |call_id, undo_state|
      Chat::Mitigation.create!(chat: chat, workspace: workspace, asker: alice, tool_call_id: call_id, tool_name: "posthog_feature_flag_disable",
                               action_key: "posthog.feature_flag_disable", arguments: {}, duration_minutes: 60, status: Chat::Mitigation::STATUS_ACTIVE,
                               started_at: Time.current, expires_at: 1.hour.from_now, undo_state: undo_state)
    end
    waiting = made.call("call_waiting", Chat::Mitigation::UNDO_WRITING)
    ready = made.call("call_ready", Chat::Mitigation::UNDO_READY)

    ActiveRecord::Migration.suppress_messages { MoveUnwrittenUndosToTheChat.new.migrate(:up) }

    assert_equal [ Chat::Mitigation::UNDO_IN_CHAT, Chat::Mitigation::IN_CHAT_NOTE ], [ waiting.reload.undo_state, waiting.undo_note ]
    assert_equal Chat::Mitigation::UNDO_READY, ready.reload.undo_state
  end
end
