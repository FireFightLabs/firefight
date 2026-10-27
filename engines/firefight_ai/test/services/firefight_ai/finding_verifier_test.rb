require "test_helper"

class FirefightAi::FindingVerifierTest < ActiveSupport::TestCase
  setup do
    FirefightAi.stubs(:bind)
    @workspace = workspaces(:slack_workspace_one)
    @choice = FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic")
  end

  test "its prompt tries to show the finding wrong, checks each step and each piece of evidence, and may confirm, strengthen or withdraw earlier findings" do
    prompt = FirefightAi::FindingVerifier.system_prompt

    [
      "your job is to find out whether it holds", "Check each step of its failure chain", "a table too small to matter makes the finding wrong",
      "Check each piece of evidence", "it confirms it", "it strengthens it", "it withdraws it", "drop it and confirm or strengthen the earlier one",
      "settle_finding once"
    ].each { |rule| assert_includes prompt, rule }
    assert_includes prompt, FirefightAi::Evidence::RULE
  end

  test "a check runs one loop on a chat of its own, with the finding framed as evidence, the earlier findings and the pull request, until it settles" do
    chat = mock("chat")
    chat.stubs(:with_tools)
    chat.stubs(:with_caching)
    chat.expects(:with_instructions).with(FirefightAi::FindingVerifier.system_prompt, cache_until_here: true)
    chat.expects(:add_message).with(role: :user, content: all_of(
      includes("<tool_result tool=\"#{FirefightAi::FindingVerifier::FRAME_FINDING}\" trust=\"untrusted\">\nLock the draft"), includes("## Findings already written\n<tool_result tool=\"#{FirefightAi::PullRequestReviewer::FRAME_FINDINGS}\" trust=\"untrusted\">\n1. Earlier"),
      includes("## The pull request\nacme/api PR #7")
    ))
    settled = -> { true }
    FirefightAi::AgentLoop.expects(:new).with do |**given|
      given[:answered] == settled && given[:budget].max_turns == FirefightAi::FindingVerifier::MAX_TURNS && given[:budget].max_spend_cents == 30 &&
        given[:inference][:feature] == FirefightAi::FindingVerifier::FEATURE && given[:purpose] == AiPurpose::CODE_REVIEW && !given[:reply_is_answer]
    end.returns(stub(run: :outcome))

    outcome = FirefightAi::FindingVerifier.new(@workspace, inferable: nil, choice: @choice)
                                          .run(chat: chat, tools: [], finding: "Lock the draft", earlier: "1. Earlier", context: "acme/api PR #7", max_spend_cents: 30, settled: settled)

    assert_equal :outcome, outcome
  end

  test "with nothing written yet, the check is told so" do
    chat = mock("chat")
    chat.stubs(:with_tools)
    chat.stubs(:with_caching)
    chat.stubs(:with_instructions)
    chat.expects(:add_message).with(role: :user, content: includes("## Findings already written\n(none yet)"))
    FirefightAi::AgentLoop.stubs(:new).returns(stub(run: :outcome))

    FirefightAi::FindingVerifier.new(@workspace, inferable: nil, choice: @choice)
                                .run(chat: chat, tools: [], finding: "x", earlier: "", context: "y", max_spend_cents: 30, settled: -> { true })
  end
end
