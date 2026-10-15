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

  test "the list's preview and its search read Halon's answer without the markers that place its charts" do
    @conversation.ask!("How is memory?")
    @conversation.note!("Memory of web climbed.\n\n{{chart:3f9a1c2e}}\n\nThe job held.")

    assert_equal "Memory of web climbed.\n\nThe job held.", @conversation.reload.preview
    member = workspace_memberships(:alice_workspace_one)
    assert_empty Conversation.search_for(member, "3f9a1c2e")
    assert_equal [ @conversation ], Conversation.search_for(member, "the job held")
  end

  # Seen in a real chat, the page waited on a turn whose worker was gone.
  test "an answer owed for longer than the reply ceiling counts as abandoned" do
    @conversation.ask!("What changed today?")
    @conversation.update_columns(answer_owed_since: (Conversation::REPLY_CEILING + 1.minute).ago)

    assert_not @conversation.answer_owed?
  end

  test "a picked model runs the chat from its next turn, and its first chat opens on it" do
    add_ai_account!(@workspace, provider: "openrouter", key: "sk-or-own")
    @conversation.update_columns(updated_at: 2.days.ago)

    @conversation.choose_model!("z-ai/glm-5.2")

    assert_equal "z-ai/glm-5.2", @conversation.reload.chosen_model
    assert_equal [ "z-ai/glm-5.2", "openrouter" ], @conversation.ai_model.to_h.values_at(:model, :provider)
    assert_equal "openai/shared-vision", @conversation.workspace_model.model
    assert_equal "z-ai/glm-5.2", @conversation.chat_record.model_id
    assert_operator @conversation.updated_at, :<, 1.day.ago, "picking a model is not talking, so the chat keeps its place"
  end

  test "picking the main model clears the pick, and a pick no longer offered runs on the main model" do
    add_ai_account!(@workspace, provider: "openrouter", key: "sk-or-own")
    @conversation.choose_model!("z-ai/glm-5.2")
    @conversation.choose_model!("openai/shared-vision")
    assert_nil @conversation.reload.chosen_model

    @conversation.update_columns(chosen_model: "deepseek/deepseek-v4-pro")
    assert_equal "openai/shared-vision", @conversation.ai_model.model
  end

  test "a chat in a Slack thread keeps the workspace's model whatever is stored on it" do
    add_ai_account!(@workspace, provider: "openrouter", key: "sk-or-own")
    channel = @workspace.conversations.create!(kind: Conversation::KIND_CHANNEL, channel_id: "C1", thread_id: "1.1", max_turns: 5, max_spend_cents: 5,
                                               chosen_model: "z-ai/glm-5.2")

    assert_nil channel.picked_model_choice
    assert_equal "openai/shared-vision", channel.ai_model.model
  end

  test "owing an answer does not move the chat up the list" do
    @conversation.update_columns(updated_at: 2.days.ago)

    @conversation.expect_reply!

    assert_in_delta 2.days.ago, @conversation.reload.updated_at, 5
  end
end
