require "test_helper"

class AgentChatModelsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    add_ai_account!(@workspace, provider: "openrouter", key: "sk-or-own")
  end

  test "a new chat offers the models the workspace's account can run, starting on its main model" do
    get agent_chats_url, headers: inertia_headers

    menu = inertia_props[AgentChatsController::PROP_CHAT_MODELS]
    assert_equal "openai/shared-vision", menu["selected"]
    assert_equal [ "openai/shared-vision", "z-ai/glm-5.2", "anthropic/claude-sonnet-5.5", "anthropic/claude-opus-5.5" ], menu["models"].pluck("id")
    assert_equal({ "id" => "z-ai/glm-5.2", "label" => "GLM-5.2", "note" => "Fast and low cost for everyday questions", "default" => false,
                   "imagesUnread" => Chat::Attachment::IMAGES_UNREAD }, menu["models"].second)
  end

  test "with one model to run there is no picker" do
    @workspace.workspace_ai_accounts.destroy_all

    get agent_chats_url, headers: inertia_headers

    assert_nil inertia_props[AgentChatsController::PROP_CHAT_MODELS]
  end

  test "switching an open chat's model says so, and the chat shows it" do
    conversation = start_chat

    patch agent_chat_url(conversation), params: { model: "anthropic/claude-opus-5.5" }

    assert_equal "This chat now uses Claude Opus 5.5.", flash[:notice]
    assert_equal "anthropic/claude-opus-5.5", conversation.reload.chosen_model
    get agent_chat_url(conversation), headers: inertia_headers
    assert_equal "anthropic/claude-opus-5.5", inertia_props.dig(AgentChatsController::PROP_CHAT_MODELS, "selected")
  end

  test "switching back to the main model says so and follows the workspace again" do
    conversation = start_chat
    conversation.choose_model!("z-ai/glm-5.2")

    patch agent_chat_url(conversation), params: { model: "openai/shared-vision" }

    assert_equal "This chat now uses Shared Vision.", flash[:notice]
    assert_nil conversation.reload.chosen_model
  end

  test "a model the workspace's account cannot run is refused with the reason" do
    conversation = start_chat

    patch agent_chat_url(conversation), params: { model: "deepseek/deepseek-v4-pro" }

    assert_equal Conversation::ModelMenu::NOT_OFFERED, flash[:alert]
    assert_nil conversation.reload.chosen_model
  end

  test "a model picked before the first question starts the chat on it" do
    post agent_chats_url, params: { question: "what changed today", model: "z-ai/glm-5.2" }

    conversation = @workspace.conversations.personal.find_by!(started_by: @member)
    assert_redirected_to agent_chat_path(conversation)
    assert_equal "z-ai/glm-5.2", conversation.chosen_model
    assert_equal "z-ai/glm-5.2", conversation.chat.model_id
  end

  test "a new chat on a model not offered is never created" do
    assert_no_difference -> { @workspace.conversations.personal.count } do
      post agent_chats_url, params: { question: "what changed today", model: "deepseek/deepseek-v4-pro" }
    end

    assert_redirected_to agent_chats_url
    assert_equal Conversation::ModelMenu::NOT_OFFERED, flash[:alert]
  end

  test "someone else's chat cannot be switched" do
    theirs = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:bob_workspace_one))

    patch agent_chat_url(theirs), params: { model: "z-ai/glm-5.2" }

    assert_response :not_found
    assert_nil theirs.reload.chosen_model
  end

  test "each of Halon's messages names the model that wrote it, and a person's names none" do
    conversation = start_chat
    conversation.ask!("what changed today")
    reply = conversation.chat.add_message(role: Chat::Message::ROLE_ASSISTANT, content: "Nothing changed.")
    RubyLLM::ActiveRecord::Usage.create!(chat: conversation.chat, message: reply, operation: "chat", provider: "openrouter",
                                         model: "anthropic/claude-sonnet-5.5", status: "failed")
    RubyLLM::ActiveRecord::Usage.create!(chat: conversation.chat, message: reply, operation: "chat", provider: "openrouter",
                                         model: "z-ai/glm-5.2", status: "succeeded")

    get agent_chat_url(conversation), headers: inertia_headers

    assert_equal [ nil, "GLM-5.2" ], inertia_props["messages"].pluck("model")
  end

  private

  def start_chat
    Conversation.start_personal!(workspace: @workspace, member: @member)
  end
end
