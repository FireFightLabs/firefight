require "test_helper"

# Asking Halon from beside a workflow's canvas starts the person's own chat about that workflow, or carries it on.
class WorkflowChatsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Release check")
    sign_in(users(:bob), @workspace)
  end

  def beside = Conversation.beside(@workflow, @bob)

  test "the first question starts a chat about the workflow, answered in the background, and the canvas shows it" do
    assert_enqueued_with(job: ConversationReplyJob) do
      post workflow_chat_url(@workflow), params: { question: "Add a step that waits for the deploy." }
    end

    assert_redirected_to workflow_path(@workflow)
    chat = beside
    assert_equal [ Conversation::KIND_PERSONAL, @workflow ], [ chat.kind, chat.subject ]

    get workflow_url(@workflow), headers: inertia_headers
    assert_equal chat.id, inertia_props["chat"]["id"]
    assert_equal [ "Add a step that waits for the deploy." ], inertia_props["chatMessages"].map { |message| message["body"] }
    assert_nil inertia_props["chatUnavailable"]
  end

  test "the chat beside the canvas carries the charts Halon drew in it, with the handles its answers place them by" do
    post workflow_chat_url(@workflow), params: { question: "How much memory does the check use?" }
    started = Time.utc(2026, 9, 25, 14, 0)
    Chat::Chart.record!(beside.chat, "call_1", [ { "title" => "Memory of web", "unit" => "MB", "from" => started.iso8601, "to" => (started + 1.hour).iso8601,
                                                   "series" => [ { "label" => "web-1", "points" => [ [ started.iso8601, 1 ] ] } ] } ])

    get workflow_url(@workflow), headers: inertia_headers.merge("X-Inertia-Partial-Data" => WorkflowCanvasController::PROP_CHARTS,
                                                                 "X-Inertia-Partial-Component" => "halon/workflow")

    chart = beside.chat.charts.sole
    assert_equal [ [ chart.handle, "call_1" ] ], inertia_props[WorkflowCanvasController::PROP_CHARTS].map { |each| each.values_at("handle", "toolCallId") }
  end

  test "a later question carries the chat on, and a new chat leaves the old one in the person's chats" do
    post workflow_chat_url(@workflow), params: { question: "What does it do?" }
    first = beside
    first.update!(answer_owed_since: nil)

    post workflow_chat_url(@workflow), params: { question: "And then?" }
    assert_equal first, beside

    post workflow_chat_url(@workflow), params: { question: "Start over.", fresh: true }
    assert_not_equal first, beside
    assert_equal 2, @workspace.conversations.own_for(@bob).where(subject: @workflow).count
  end

  test "nothing asked is refused" do
    post workflow_chat_url(@workflow), params: { question: " " }

    assert_redirected_to workflow_path(@workflow)
    assert_equal "Say something first.", flash[:alert]
    assert_nil beside
  end

  test "a workspace without Halon is told why on the canvas, and the canvas says so too" do
    deny_entitlements!

    post workflow_chat_url(@workflow), params: { question: "What does it do?" }

    assert_redirected_to workflow_path(@workflow)
    assert_equal Investigation.unavailable_reason(@workspace), flash[:alert]
    get workflow_url(@workflow), headers: inertia_headers
    assert_equal Investigation.unavailable_reason(@workspace), inertia_props["chatUnavailable"]
  end

  test "with no answer on its way there is nothing to stop" do
    post workflow_chat_stop_url(@workflow)

    assert_equal Conversation::NOTHING_TO_STOP, flash[:alert]
  end

  test "an answer on its way is stopped" do
    post workflow_chat_url(@workflow), params: { question: "What does it do?" }
    beside.update!(answer_owed_since: Time.current)
    Conversation.any_instance.expects(:request_stop!)
    post workflow_chat_stop_url(@workflow)

    assert_redirected_to workflow_path(@workflow)
    assert_equal Conversation::STOPPING, flash[:notice]
  end
end
