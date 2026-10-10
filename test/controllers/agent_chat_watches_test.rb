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

  test "the chat shows the watch going, named for what it waits on, how long and why, its ceiling on reads, the run's page, and that its asker may stop it" do
    @watch.update!(title: "Release run #46 passed", reads_total: 14)
    @watch.steps.sole.update!(run_url: "https://github.com/acme/firefight/actions/runs/46")
    get agent_chat_url(@conversation), headers: inertia_headers

    shown = inertia_props[AgentChatsController::PROP_WATCHES].sole
    assert_equal 'Watch "Release run #46 passed"', shown["headline"]
    assert_equal "Up to 40 min. It usually takes about 18 minutes.", shown["basis"]
    assert_equal "Reads at most 120 times an hour. 14 reads so far.", shown["reads"]
    assert_equal [ [ "Release run #46", "https://github.com/acme/firefight/actions/runs/46" ] ], shown["steps"].map { |step| step.values_at("label", "url") }
    assert_nil shown["stopBlockedReason"]
  end

  test "Stop ends it with a toast, and the line it said joins the chat" do
    post agent_chat_watch_stop_url(@conversation, @watch)

    assert_redirected_to agent_chat_url(@conversation)
    assert_equal 'Stopped watching "release run #46".', flash[:notice]
    assert_equal Chat::Watch::STATUS_STOPPED, @watch.reload.status

    get agent_chat_url(@conversation), headers: inertia_headers
    assert_equal 'Watch "release run #46": stopped', inertia_props[AgentChatsController::PROP_WATCHES].sole["headline"]
    assert_equal [ "#{@member.display_name} stopped the watch \"release run #46\"." ],
                 inertia_props[AgentChatsController::PROP_WATCH_UPDATES].map { |update| update["text"] }
    assert_equal [ 'Watch "release run #46"' ], inertia_props[AgentChatsController::PROP_WATCH_UPDATES].map { |update| update["name"] }
  end

  test "a watch that already ended says so rather than stopping twice" do
    @watch.finish!(Chat::Watch::STATUS_SUCCEEDED, outcome: "Done.")

    post agent_chat_watch_stop_url(@conversation, @watch)

    assert_equal Chat::Watch::NOTHING_TO_STOP, flash[:alert]
  end
end
