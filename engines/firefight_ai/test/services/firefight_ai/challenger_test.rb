require "test_helper"

# A second look at a named cause, by a separate quick call whose only job is evidence against it.
class FirefightAi::ChallengerTest < ActiveSupport::TestCase
  setup do
    @challenger = FirefightAi::Challenger.new(workspaces(:slack_workspace_one), inferable: nil, choice: FirefightAi::ModelChoice.new(model: "gpt-4o-mini"))
  end

  test "its own prompt looks only for evidence against the cause, and never doubts it for want of more reading" do
    prompt = FirefightAi::Challenger.system_prompt

    assert_includes prompt, "Your only job is to look for evidence against it"
    assert_includes prompt, "Do not doubt a cause only because more could be read"
    assert_includes prompt, "at most #{FirefightAi::Challenger::MAX_CHECKS} reads"
    assert_not_equal FirefightAi::Responder.new(workspaces(:slack_workspace_one), inferable: nil).prompt_version, FirefightAi::Challenger.prompt_version
  end

  test "reads what it found and at most two reads to settle it, and anything it does not recognise holds" do
    stub_model(verdict: "stronger_alternative", reason: "orders filled at 13:36, before the deploy.", checks: [ "a", "b", "c" ])
    verdict = @challenger.challenge(cause: "worker's deploy", reads: "search_logs: pool 40")

    assert_not verdict.holds?
    assert_equal [ "orders filled at 13:36, before the deploy.", %w[a b] ], [ verdict.reason, verdict.checks ]

    stub_model(verdict: "maybe")
    assert @challenger.challenge(cause: "worker's deploy", reads: "").holds?
  end

  private

  def stub_model(content)
    chat = mock("chat")
    chat.stubs(:with_max_output_tokens).returns(chat)
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:with_schema).returns(chat)
    chat.stubs(:ask).returns(llm_reply(content: content, input: 100, output: 20, cost: 0.0001))
    RubyLLM.stubs(:chat).returns(chat)
  end
end
