require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
  end

  test "an answer is owed from the question until the reply is delivered" do
    assert_not @conversation.answer_owed?

    @conversation.ask!("What changed today?")
    assert @conversation.answer_owed?

    @conversation.reply_delivered!
    assert_not @conversation.answer_owed?
  end

  # Seen in a real chat, the page waited on a turn whose worker was gone.
  test "an answer owed for longer than the reply ceiling counts as abandoned" do
    @conversation.ask!("What changed today?")
    @conversation.update_columns(answer_owed_since: (Conversation::REPLY_CEILING + 1.minute).ago)

    assert_not @conversation.answer_owed?
  end

  test "owing an answer does not move the chat up the list" do
    @conversation.update_columns(updated_at: 2.days.ago)

    @conversation.expect_reply!

    assert_in_delta 2.days.ago, @conversation.reload.updated_at, 5
  end
end
