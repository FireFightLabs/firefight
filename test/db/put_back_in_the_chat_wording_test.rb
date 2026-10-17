require "test_helper"
require Rails.root.join("db/migrate/20261017120100_say_a_change_put_back_in_the_chat_is_marked_back")
require Rails.root.join("db/migrate/20261017120200_move_undos_by_hand_to_the_chat")

class PutBackInTheChatWordingTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @chat = Conversation.start_personal!(workspace: @workspace, member: @alice).chat_record
  end

  test "a change waiting to be put back in the chat says it is marked back once it is, and a note someone else wrote is left" do
    old = made("call_old", undo_state: Chat::Mitigation::UNDO_IN_CHAT, undo_note: "Halon is asked in the chat to put it back, and that call asks first like any change.")
    older = made("call_older", undo_state: Chat::Mitigation::UNDO_IN_CHAT, undo_note: "Halon puts it back in the chat, and asks first like any change.")
    other = made("call_other", undo_state: Chat::Mitigation::UNDO_READY, undo_note: "Turn the flag back on.")

    ActiveRecord::Migration.suppress_messages { SayAChangePutBackInTheChatIsMarkedBack.new.migrate(:up) }

    assert_equal [ Chat::Mitigation::IN_CHAT_NOTE ] * 2, [ old.reload.undo_note, older.reload.undo_note ]
    assert_equal "Turn the flag back on.", other.reload.undo_note
  end

  test "a change due by hand goes to the chat like the rest, and one still running is put back in the chat when due" do
    due = made("call_due", status: MoveUndosByHandToTheChat::DUE_BY_HAND, undo_state: MoveUndosByHandToTheChat::BY_HAND, undo_note: "Undo it by hand.")
    running = made("call_running", undo_state: MoveUndosByHandToTheChat::BY_HAND, undo_note: "Undo it by hand.")

    ActiveRecord::Migration.suppress_messages { MoveUndosByHandToTheChat.new.migrate(:up) }

    assert_equal [ Chat::Mitigation::STATUS_UNDO_ASKED, Chat::Mitigation::UNDO_IN_CHAT, Chat::Mitigation::IN_CHAT_NOTE ],
                 [ due.reload.status, due.undo_state, due.undo_note ]
    assert due.reminded_at, "it was already said to be due by hand, so it is not said again"
    assert due.told_at, "Halon is not nudged to put back what may already be back by hand"
    assert running.reload.told_at
    assert_equal [ Chat::Mitigation::STATUS_ACTIVE, Chat::Mitigation::UNDO_IN_CHAT ], [ running.reload.status, running.undo_state ]
  end

  private

  # Written as the row stood before, in states the app no longer makes.
  def made(call_id, status: Chat::Mitigation::STATUS_ACTIVE, **attributes)
    Chat::Mitigation.create!(chat: @chat, workspace: @workspace, asker: @alice, tool_call_id: call_id, tool_name: "posthog_feature_flag_disable",
                             action_key: "posthog.feature_flag_disable", arguments: {}, duration_minutes: 60, status: Chat::Mitigation::STATUS_ACTIVE,
                             started_at: Time.current, expires_at: 1.hour.from_now).tap { |row| row.update_columns(status: status, **attributes) }
  end
end
