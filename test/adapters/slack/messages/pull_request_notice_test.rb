require "test_helper"

class Slack::Messages::PullRequestNoticeTest < ActiveSupport::TestCase
  setup do
    @bob = workspace_memberships(:bob_workspace_one)
    session = CodeAgentSession.create!(workspace: @bob.workspace, provider: "anthropic", model: "m", repository: "acme/api", budget_micros: 1,
                                       expires_at: 1.hour.from_now, token_digest: SecureRandom.hex, principal: @bob, pull_request_number: 689,
                                       pull_request_url: "https://github.com/acme/api/pull/689", pull_request_state: Integrations::PullRequests::OPEN)
    @notice = CodeAgentSession::Notice.create!(session: session, workspace: @bob.workspace, fingerprint: "f", base: "main", status: CodeAgentSession::Notice::STATUS_OFFERED,
                                               problems: [ { "kind" => Integrations::PullRequests::PROBLEM_CONFLICT } ])
  end

  test "an offer says why and what Fix it does below a divider, with Fix it, and in direct messages a way to the chat" do
    Slack::DashboardUrl.stubs(:agent_chat).returns("https://ff.example.com/app/agent/c1")

    blocks = Slack::Messages::PullRequestNotice.build(@notice, conversation_id: "c1")

    assert_equal ":warning:  *PR #689 in acme/api needs attention*", blocks.first.dig(:text, :text)
    assert_equal "divider", blocks.second[:type]
    assert_match "It conflicts with main now.", blocks.third.dig(:text, :text)
    assert_match "Nothing changes until it is pressed.", blocks.third.dig(:text, :text)
    buttons = blocks.last[:elements]
    assert_equal [ "Fix it", Identifiers::PULL_REQUEST_FIX, @notice.id, "primary" ], buttons.first.values_at(:text, :action_id, :value, :style).then { |text, *rest| [ text[:text], *rest ] }
    assert_equal "Open the chat", buttons.second.dig(:text, :text)
  end

  test "once pressed it says who pressed it and offers nothing" do
    @notice.claim_fix!(@bob)

    blocks = Slack::Messages::PullRequestNotice.build(@notice)

    assert_equal ":hammer_and_wrench:  *PR #689 in acme/api needs attention*", blocks.first.dig(:text, :text)
    assert_equal "Fix it pressed by Bob Jones. Halon says how it went in the chat.", blocks.last.dig(:elements, 0, :text)
    assert_not(blocks.any? { |block| block[:type] == "actions" })
  end
end
