require "test_helper"

# A chat in the dashboard belongs to the person who started it, and exists only where the agent does.
class AgentChatsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "the page is reachable once the agent is turned on" do
    get agent_chats_url, headers: inertia_headers

    assert_response :success
    assert_equal [], inertia_props["conversations"]
  end

  test "an open chat arrives with what has been said in it" do
    conversation = start_chat
    chat = Chat.open!(
      owner: conversation, workspace: @workspace, model_choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil)
    )
    chat.messages.create!(role: Chat::Message::ROLE_USER, content: "What changed today?")

    get agent_chat_url(conversation), headers: inertia_headers

    assert_equal "What changed today?", inertia_props["messages"].sole["body"]
    assert_equal "What changed today?", inertia_props.dig("conversation", "title")
  end

  test "a workspace without the agent is sent back with the reason" do
    FeatureFlags.disable!(@workspace, FeatureFlags::AI_SRE)

    get agent_chats_url

    assert_redirected_to dashboard_path
    assert_equal Investigation.unavailable_reason(@workspace), flash[:alert]
  end

  test "starting a chat opens it" do
    assert_difference -> { @workspace.conversations.personal.count }, 1 do
      post agent_chats_url
    end

    conversation = @workspace.conversations.personal.find_by!(started_by: @member)
    assert_redirected_to agent_chat_path(conversation)
  end

  test "a question is answered in the background" do
    conversation = start_chat

    assert_enqueued_with(job: ConversationReplyJob, args: [ conversation.id, "what changed today" ]) do
      post agent_chat_ask_url(conversation), params: { question: "what changed today" }
    end

    assert_redirected_to agent_chat_path(conversation)
  end

  test "an empty question is not sent to the model" do
    conversation = start_chat

    assert_no_enqueued_jobs(only: ConversationReplyJob) do
      post agent_chat_ask_url(conversation), params: { question: "   " }
    end

    assert_equal "Say something first.", flash[:alert]
  end

  test "someone else's chat is not readable" do
    theirs = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:bob_workspace_one))

    get agent_chat_url(theirs), headers: inertia_headers

    assert_response :not_found
  end

  test "a chat in another workspace is not readable" do
    elsewhere = Conversation.start_personal!(
      workspace: workspaces(:slack_workspace_two), member: workspace_memberships(:alice_workspace_two)
    )

    get agent_chat_url(elsewhere), headers: inertia_headers

    assert_response :not_found
  end

  private

  def start_chat
    post agent_chats_url
    @workspace.conversations.personal.find_by!(started_by: @member)
  end
end
