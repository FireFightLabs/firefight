require "test_helper"

# The line a reply ends with to say Halon's next step is the loop's, so it never reaches a page, a thread or a replay.
class Chat::MessageNextStepTest < ActiveSupport::TestCase
  test "a reply is saved without the line saying its next step, and a person's words are kept as they wrote them" do
    conversation = Conversation.start_personal!(workspace: workspaces(:slack_workspace_one), member: workspace_memberships(:alice_workspace_one))
    chat = conversation.chat_record

    reply = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "It was the 14:02 deploy.\n\n[next step: change]")
    said = chat.messages.create!(role: Chat::Message::ROLE_USER, content: "what does [next step: read] mean?")

    assert_equal "It was the 14:02 deploy.", reply.reload.content
    assert_equal "what does [next step: read] mean?", said.reload.content
  end
end
