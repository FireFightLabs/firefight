require "application_system_test_case"

# A pull request Halon opened from a chat that conflicts with its base after a later merge. The chat says why and what
# Fix it does, and nothing changes on the branch until the person who asked presses Fix it.
class AgentPullRequestNoticeCardTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    WorkspaceAdapter.stubs(:for).returns(stub_everything)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @conversation.ask!("Remove --output /dev/null from the release workflow and open a pull request")
    @conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "Opened PR #689. The code host says it can merge into main.")
    @conversation.reply_delivered!
    session = CodeAgentSession.create!(workspace: @workspace, provider: "anthropic", model: "m", repository: "FireFightLabs/firefight", budget_micros: 1,
                                       expires_at: 1.hour.from_now, token_digest: SecureRandom.hex, principal: @alice, place: @conversation,
                                       pull_request_number: 689, pull_request_url: "https://github.com/FireFightLabs/firefight/pull/689",
                                       pull_request_base: "main", pull_request_state: Integrations::PullRequests::OPEN)
    CodeAgentSession::Notice.create!(session: session, workspace: @workspace, conversation: @conversation, fingerprint: "f", base: "main",
                                     status: CodeAgentSession::Notice::STATUS_OFFERED, problems: [ { "kind" => Integrations::PullRequests::PROBLEM_CONFLICT } ])
  end

  test "the chat says the pull request conflicts now and what Fix it does, and Fix it starts the change with a toast" do
    visit agent_chat_path(@conversation)

    assert_text "PR #689 in FireFightLabs/firefight needs attention"
    assert_text "It conflicts with main now."
    assert_text "Fix it has Halon merge main in and resolve the conflict on the pull request's branch, as Alice Smith. Nothing changes until it is pressed."
    assert_link "Open the pull request", href: "https://github.com/FireFightLabs/firefight/pull/689"

    click_on "Fix it"

    assert_text "Halon is fixing PR #689 in FireFightLabs/firefight."
    assert_text "Fix it pressed by Alice Smith. Halon says how it went below."
    assert_no_button "Fix it"
  end
end
