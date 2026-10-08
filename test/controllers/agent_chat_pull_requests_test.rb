require "test_helper"

class AgentChatPullRequestsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    session = CodeAgentSession.create!(workspace: @workspace, provider: "anthropic", model: "m", repository: "acme/api", budget_micros: 1,
                                       expires_at: 1.hour.from_now, token_digest: SecureRandom.hex, principal: @member, place: @conversation,
                                       pull_request_number: 689, pull_request_url: "https://github.com/acme/api/pull/689",
                                       pull_request_state: Integrations::PullRequests::OPEN)
    @notice = CodeAgentSession::Notice.create!(session: session, workspace: @workspace, conversation: @conversation, fingerprint: "f", base: "main",
                                               status: CodeAgentSession::Notice::STATUS_OFFERED, problems: [ { "kind" => Integrations::PullRequests::PROBLEM_CONFLICT } ])
    ConversationChannel.stubs(:broadcast_to)
  end

  test "the chat shows a pull request Halon opened that needs attention, with why and Fix it for whoever asked" do
    get agent_chat_url(@conversation), headers: inertia_headers

    shown = inertia_props[AgentChatsController::PROP_PULL_REQUEST_NOTICES].sole
    assert_equal [ "PR #689 in acme/api needs attention", "offered", "https://github.com/acme/api/pull/689" ], shown.values_at("headline", "status", "url")
    assert_equal "It conflicts with main now.", shown["reason"]
    assert_nil shown["fixBlockedReason"]
  end

  test "Fix it starts the change in the chat with a toast, and a second press says it was already taken care of" do
    assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, @member.id, nil, nil, @notice.id ]) do
      post agent_chat_pull_request_fix_url(@conversation, @notice)
    end

    assert_redirected_to agent_chat_url(@conversation)
    assert_equal "Halon is fixing PR #689 in acme/api.", flash[:notice]
    assert_equal CodeAgentSession::Notice::STATUS_FIXING, @notice.reload.status

    post agent_chat_pull_request_fix_url(@conversation, @notice)
    assert_equal "This was already taken care of.", flash[:alert]
  end
end
