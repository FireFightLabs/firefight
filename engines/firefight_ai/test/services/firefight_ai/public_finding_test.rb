require "test_helper"

class FirefightAi::PublicFindingTest < ActiveSupport::TestCase
  test "a finding is written again in code terms, its chain in order, with the team's words read as evidence" do
    asked = nil
    chat = mock("chat")
    chat.stubs(:with_max_output_tokens).returns(chat)
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:with_schema).returns(chat)
    content = { why: "The retry runs with no wait.", failure_chain: [ "perform_later has no wait", " " ] }
    reply = llm_reply(content: content, input: 100, output: 20, cost: 0.0001)
    reply.stubs(:parsed).returns(content.deep_stringify_keys)
    chat.stubs(:ask).with { |text| (asked = text) || true }.returns(reply)
    RubyLLM.stubs(:chat).returns(chat)

    rewritten = FirefightAi::PublicFinding.new(workspaces(:slack_workspace_one), choice: FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic"))
                                          .rewrite(claim: "Queue the retry", why: "As in INC-012, checkout retries went up.", failure_chain: [ "payments-api retries" ])

    assert_equal [ "The retry runs with no wait.", [ "perform_later has no wait" ] ], [ rewritten.why, rewritten.failure_chain ]
    assert_includes asked, "<tool_result tool=\"finding\" trust=\"untrusted\">\nAs in INC-012"
    assert_includes FirefightAi::PublicFinding::PROMPT, FirefightAi::Copy::RULE
  end
end
