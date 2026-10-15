require "test_helper"

# Seen live: each message sent read the whole open chat back, every card under it included, for 1.4 seconds. Each change
# made from a chat reads back only what it changed, and nothing else on the page is worked out for it.
class AgentChatInPlaceTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @conversation.ask!("what is open")
    @conversation.note!("Nothing is open.")
    @conversation.reply_delivered!
  end

  test "a question reads back the chat's state and its messages, never the list of chats or the cards" do
    headers = inertia_partial_headers("agent/index", AgentChatsController::ASKED_PROPS)
    post agent_chat_ask_url(@conversation), params: { question: "and now?" }, headers: headers
    assert_redirected_to agent_chat_path(@conversation)

    nothing_else_worked_out
    get agent_chat_url(@conversation), headers: headers

    assert_equal AgentChatsController::ASKED_PROPS.sort, (inertia_props.keys - [ "errors" ]).sort
    assert_equal [ "and now?", "Nothing is open.", "what is open" ], inertia_props["messages"].map { |message| message["body"] }
    assert inertia_props["conversation"]["busy"]
  end

  test "answering confirmations reads back the cards and the steps they held, never the list of chats" do
    headers = inertia_partial_headers("agent/index", AgentChatsController::DECIDED_PROPS)
    post agent_chat_confirm_url(@conversation), params: { decisions: [] }, headers: headers, as: :json
    assert_redirected_to agent_chat_path(@conversation)

    AgentChatSerializer.expects(:many).never
    AgentChatHeldCallSerializer.expects(:many).never
    get agent_chat_url(@conversation), headers: headers

    assert_equal AgentChatsController::DECIDED_PROPS.sort, (inertia_props.keys - [ "errors" ]).sort
  end

  test "asking beside a workflow's canvas reads back only the chat, never the canvas" do
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    workflow = Workflow.create!(workspace: @workspace, name: "Release check")
    headers = inertia_partial_headers("halon/workflow", WorkflowCanvasController::CHAT_PROPS)
    post workflow_chat_url(workflow), params: { question: "What does it do?" }, headers: headers
    assert_redirected_to workflow_path(workflow)

    [ WorkflowDetailSerializer, WorkflowDocumentSerializer, WorkflowRunRowSerializer, WorkflowVersionRowSerializer, WorkflowSuggestionSerializer,
      WorkflowHalonChangeSerializer, WorkflowStepKindSerializer, WorkflowTriggerKindSerializer ].each do |serializer|
      serializer.expects(:one).never
      serializer.expects(:many).never
    end
    get workflow_url(workflow), headers: headers

    assert_equal WorkflowCanvasController::CHAT_PROPS.sort, (inertia_props.keys - [ "errors" ]).sort
    assert_equal [ "What does it do?" ], inertia_props["chatMessages"].map { |message| message["body"] }
  end

  private

  def nothing_else_worked_out
    AgentChatSerializer.expects(:many).never
    AgentChatIncidentSerializer.expects(:many).never
    AgentChatHeldCallSerializer.expects(:many).never
    AgentChatPlanSerializer.expects(:many).never
    AgentChatConfirmationSerializer.expects(:many).never
  end
end
