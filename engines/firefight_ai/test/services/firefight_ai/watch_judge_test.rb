require "test_helper"

class FirefightAi::WatchJudgeTest < ActiveSupport::TestCase
  setup do
    @judge = FirefightAi::WatchJudge.new(workspaces(:slack_workspace_one))
  end

  test "a reading is not started, running, done or failed with the jobs it lists, and a state it does not know moves nothing" do
    stub_model(content: { state: "done", said: "web runs the new version.", parts: [] })
    assert_equal [ "done", "web runs the new version." ], reading_of(@judge.reading(goal: "web is live", before: nil, now: "web is live", so_far: "not started"))

    stub_model(content: { state: "running", said: "The release run is going.",
                          parts: [ { name: "tag", state: "passed" }, { name: "trigger-northflank", state: "running" }, { name: "", state: "passed" },
                                   { name: "build", state: "maybe" } ] })
    reading = @judge.reading(goal: "the release finishes", before: "queued", now: "in_progress", so_far: "not started")
    assert_equal FirefightAi::Schemas::WatchReading::RUNNING, reading.state
    assert_equal [ %w[tag passed], %w[trigger-northflank running] ], reading.parts

    stub_model(content: { state: "maybe", said: "" })
    assert_nil @judge.reading(goal: "web is live", before: "a", now: "b", so_far: "running").state
  end

  test "why something failed is said from the evidence, and nothing when the evidence does not show it" do
    stub_model(content: "The user model test failed.")
    assert_equal "The user model test failed.", @judge.why_failed(what: "Release run #46", evidence: "FAILED test/models/user_test.rb")

    stub_model(content: "unknown")
    assert_nil @judge.why_failed(what: "Release run #46", evidence: "exit 1")
  end

  test "where something leaves the person's goal is said with the next step as a question, and nothing when nothing useful can be said" do
    stub_model(content: "The GitHub path is still broken. Next I would read the webhook's error, shall I?")
    chat = RubyLLM.chat
    chat.expects(:ask).with { |text| text.include?("fix the release webhook") && text.include?("Manual run succeeded.") }
        .returns(llm_reply(content: "The GitHub path is still broken. Next I would read the webhook's error, shall I?", input: 100, output: 20, cost: 0.0001))
    assert_equal "The GitHub path is still broken. Next I would read the webhook's error, shall I?",
                 @judge.standing(purpose: "fix the release webhook", happened: "Manual run succeeded.")

    stub_model(content: "unknown")
    assert_nil @judge.standing(purpose: "fix the release webhook", happened: "Started.")
  end

  test "the standing prompt never claims a goal met or a fix without what happened showing it" do
    prompt = FirefightAi::WatchJudge::STANDING_PROMPT
    assert_match "Never say the goal is reached unless what happened shows it", prompt
    assert_match "offer the check that would show it", prompt
    assert_match "shall I?", prompt
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
