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
    conversation.ask!("What changed today?")

    get agent_chat_url(conversation), headers: inertia_headers

    assert_equal "What changed today?", inertia_props["messages"].sole["body"]
    assert_equal "What changed today?", inertia_props.dig("conversation", "title")
  end

  test "the model's own scaffolding is not read back to the person" do
    conversation = start_chat
    conversation.ask!("What changed today?")
    conversation.chat.messages.create!(role: "system", content: "You are Firefight, answering an engineer")
    conversation.chat.messages.create!(role: "tool", content: '{"incidents":[{"identifier":"INC-1"}]}')

    get agent_chat_url(conversation), headers: inertia_headers

    assert_equal [ "What changed today?" ], inertia_props["messages"].map { |message| message["body"] }
  end

  test "a workspace without the agent is sent back with the reason" do
    FeatureFlags.disable!(@workspace, FeatureFlags::AI_SRE)

    get agent_chats_url

    assert_redirected_to dashboard_path
    assert_equal Investigation.unavailable_reason(@workspace), flash[:alert]
  end

  test "the first question starts the chat and is answered in the background" do
    assert_difference -> { @workspace.conversations.personal.count }, 1 do
      post agent_chats_url, params: { question: "what changed today" }
    end

    conversation = @workspace.conversations.personal.find_by!(started_by: @member)
    assert_redirected_to agent_chat_path(conversation)
    assert_equal "what changed today", conversation.title
    assert_enqueued_with(job: ConversationReplyJob, args: [ conversation.id ])
  end

  test "a new chat with nothing asked is never created" do
    assert_no_difference -> { @workspace.conversations.personal.count } do
      post agent_chats_url, params: { question: "  " }
    end

    assert_redirected_to agent_chats_url
    assert_equal "Say something first.", flash[:alert]
  end

  test "a question is answered in the background" do
    conversation = start_chat

    assert_enqueued_with(job: ConversationReplyJob, args: [ conversation.id ]) do
      post agent_chat_ask_url(conversation), params: { question: "what changed today" }
    end

    assert_redirected_to agent_chat_path(conversation)
    assert_equal "what changed today",
                 conversation.chat.messages.where(role: Chat::Message::ROLE_USER).sole.content
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

  test "a chat can be renamed" do
    conversation = start_chat
    conversation.ask!("what changed today")

    patch agent_chat_url(conversation), params: { title: "Checkout latency" }

    assert_equal "Checkout latency", conversation.reload.title
    assert_equal "Chat renamed.", flash[:notice]
  end

  test "a chat cannot be renamed to nothing" do
    conversation = start_chat
    conversation.ask!("what changed today")

    patch agent_chat_url(conversation), params: { title: "   " }

    assert_equal "what changed today", conversation.reload.title
    assert_equal "A chat needs a name.", flash[:alert]
  end

  test "pinning puts a chat at the top of the list" do
    older = start_chat
    older.ask!("first question")
    newer = Conversation.start_personal!(workspace: @workspace, member: @member)
    newer.ask!("second question")

    patch agent_chat_url(older), params: { pinned: true }

    assert older.reload.pinned?
    assert_equal [ older.id, newer.id ], @workspace.conversations.personal.in_reading_order.map(&:id)
  end

  test "archiving from the list keeps the person where they were" do
    conversation = start_chat

    patch agent_chat_url(conversation), params: { archived: true }, headers: { "Referer" => agent_chats_url }

    assert conversation.reload.archived?
    assert_redirected_to agent_chats_url
    assert_equal "Chat archived.", flash[:notice]
  end

  test "an archived chat is still listed, so the page can offer it under its own filter" do
    conversation = start_chat
    conversation.archive!(true)

    get agent_chats_url, headers: inertia_headers

    listed = inertia_props["conversations"].map { |chat| [ chat["id"], chat["archived"] ] }
    assert_includes listed, [ conversation.id, true ]
  end

  test "deleting a chat takes its messages with it" do
    conversation = start_chat
    conversation.ask!("what changed today")
    chat_id = conversation.chat.id

    assert_difference -> { Chat.where(id: chat_id).count }, -1 do
      delete agent_chat_url(conversation)
    end

    assert_nil Conversation.find_by(id: conversation.id)
    assert_redirected_to agent_chats_path
    assert_equal "Chat deleted.", flash[:notice]
  end

  test "someone else's chat cannot be renamed or deleted" do
    theirs = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:bob_workspace_one))

    patch agent_chat_url(theirs), params: { title: "mine now" }
    assert_response :not_found

    delete agent_chat_url(theirs)
    assert_response :not_found
    assert Conversation.exists?(theirs.id)
  end

  test "the list says what was last said in each chat" do
    conversation = start_chat
    conversation.ask!("what changed today")
    conversation.note!("Two deploys went out.")

    get agent_chats_url, headers: inertia_headers

    listed = inertia_props["conversations"].find { |chat| chat["id"] == conversation.id }
    assert_equal "Two deploys went out.", listed["preview"]
  end

  private

  def start_chat
    Conversation.start_personal!(workspace: @workspace, member: @member)
  end
end
