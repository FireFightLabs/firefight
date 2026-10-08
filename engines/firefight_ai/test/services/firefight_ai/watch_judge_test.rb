require "test_helper"

class FirefightAi::WatchJudgeTest < ActiveSupport::TestCase
  setup do
    @judge = FirefightAi::WatchJudge.new(workspaces(:slack_workspace_one))
  end

  test "a reading is done, failed or going with what it shows, and anything it does not recognise is still going" do
    stub_model(content: { state: "done", said: "web runs the new version." })
    assert_equal [ "done", "web runs the new version." ], reading_of(@judge.reading(goal: "web is live", before: nil, now: "web is live"))

    stub_model(content: { state: "maybe", said: "" })
    assert_equal FirefightAi::Schemas::WatchReading::GOING, @judge.reading(goal: "web is live", before: "a", now: "b").state
  end

  test "why something failed is said from the evidence, and nothing when the evidence does not show it" do
    stub_model(content: "The user model test failed.")
    assert_equal "The user model test failed.", @judge.why_failed(what: "Release run #46", evidence: "FAILED test/models/user_test.rb")

    stub_model(content: "unknown")
    assert_nil @judge.why_failed(what: "Release run #46", evidence: "exit 1")
  end

  private

  def reading_of(said) = [ said.state, said.said ]

  def stub_model(content:)
    chat = mock("chat")
    chat.stubs(:with_max_output_tokens).returns(chat)
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:with_schema).returns(chat)
    chat.stubs(:ask).returns(llm_reply(content: content, input: 100, output: 20, cost: 0.0001))
    RubyLLM.stubs(:chat).returns(chat)
  end
end
