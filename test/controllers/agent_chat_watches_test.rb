require "test_helper"

class AgentChatWatchesTest < ActionDispatch::IntegrationTest
  include SlackClientStubHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    stub_post_message
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @watch = Chat::Watch.create!(chat: @conversation.chat_record, workspace: @workspace, asker: @member, title: "release run #46",
                                 expires_at: 40.minutes.from_now, usual_seconds: 18.minutes.to_i, limit_basis: Chat::Watch::BASIS_HISTORY)
    @watch.steps.create!(position: 0, label: "Release run #46", capability: Integrations::Capabilities::HISTORY, arguments: { "resource" => "firefight" })
  end

  test "the chat shows the watch going, with what it follows, how long and why, and that its asker may stop it" do
    get agent_chat_url(@conversation), headers: inertia_headers

    shown = inertia_props[AgentChatsController::PROP_WATCHES].sole
    assert_equal "Watching: release run #46, up to 40 min", shown["headline"]
    assert_equal "It usually takes about 18 minutes.", shown["basis"]
    assert_equal [ "Release run #46" ], shown["steps"].map { |step| step["label"] }
    assert_nil shown["stopBlockedReason"]
  end

  test "Stop ends it with a toast, and the line it said joins the chat" do
    post agent_chat_watch_stop_url(@conversation, @watch)

    assert_redirected_to agent_chat_url(@conversation)
    assert_equal "Stopped watching release run #46.", flash[:notice]
    assert_equal Chat::Watch::STATUS_STOPPED, @watch.reload.status

    get agent_chat_url(@conversation), headers: inertia_headers
    assert_equal "Stopped watching: release run #46", inertia_props[AgentChatsController::PROP_WATCHES].sole["headline"]
    assert_equal [ "#{@member.display_name} stopped the watch on release run #46." ],
                 inertia_props[AgentChatsController::PROP_WATCH_UPDATES].map { |update| update["text"] }
  end

  test "a watch that already ended says so rather than stopping twice" do
    @watch.finish!(Chat::Watch::STATUS_SUCCEEDED, outcome: "Done.")

    post agent_chat_watch_stop_url(@conversation, @watch)

    assert_equal Chat::Watch::NOTHING_TO_STOP, flash[:alert]
  end
end
