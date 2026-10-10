require "test_helper"

class Chat::StoppedNoteTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @chat = @conversation.chat_record
  end

  test "names what Halon did since its last answer, how each went, and that it stopped before deciding the next step" do
    @chat.add_message(role: :user, content: "an earlier question")
    earlier = @chat.add_message(role: :assistant, content: "")
    answered(earlier, "search_incidents", "call_old")
    @chat.add_message(role: :assistant, content: "The earlier answer.")
    @chat.add_message(role: :user, content: "restart checkout and tell me how it went")
    asking = @chat.add_message(role: :assistant, content: "")
    answered(asking, "search_incidents", "call_read")
    answered(asking, "restart", "call_restart", failed: true)

    note = Chat::StoppedNote.since_last_answer(@chat)

    assert_equal <<~NOTE.strip, note
      #{Chat::StoppedNote::HEADING}
      - Search incidents
      - Restart (a change), which failed

      #{Chat::StoppedNote::STOPPED_AFTER}
    NOTE
  end

  test "a call left running is named as where it stopped, so nobody runs a change twice" do
    asking = @chat.add_message(role: :assistant, content: "")
    answered(asking, "search_incidents", "call_read")
    asking.ruby_llm_tool_calls.create!(tool_call_id: "call_restart", name: "restart", arguments: {})

    note = Chat::StoppedNote.since_last_answer(@chat)

    assert_includes note, "- Restart, which was still running"
    assert note.end_with?("I stopped while this was still running: Restart. Check whether it finished before you try it again.")
  end

  test "nothing done since the last answer adds nothing, and a long turn names how many steps came before the latest" do
    @chat.add_message(role: :assistant, content: "Nothing to look up.")
    assert_nil Chat::StoppedNote.since_last_answer(@chat)
    assert_nil Chat::StoppedNote.since_last_answer(nil)

    asking = @chat.add_message(role: :assistant, content: "")
    (Chat::StoppedNote::SHOWN_STEPS + 2).times { |index| answered(asking, "search_incidents", "call_#{index}") }

    lines = Chat::StoppedNote.since_last_answer(@chat).lines.map(&:chomp)
    assert_equal "- 2 earlier steps", lines.second
    assert_equal Chat::StoppedNote::SHOWN_STEPS + 4, lines.size
  end

  test "a call waiting on the person is not one Halon left running" do
    asking = @chat.add_message(role: :assistant, content: "")
    asking.ruby_llm_tool_calls.create!(tool_call_id: "call_restart", name: "restart", arguments: {}, approval: Chat::APPROVAL_REQUESTED)

    assert_equal "- Restart (a change)", Chat::StoppedNote.since_last_answer(@chat).lines.second.chomp
  end

  private

  def answered(asking, name, id, failed: false)
    asking.ruby_llm_tool_calls.create!(tool_call_id: id, name: name, arguments: {})
    @chat.add_message(role: :tool, content: "ran", tool_call_id: id)
    @chat.mark_failed!(id) if failed
  end
end
