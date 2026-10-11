require "test_helper"

class FirefightAi::WatchJudgeTest < ActiveSupport::TestCase
  setup do
    @judge = FirefightAi::WatchJudge.new(workspaces(:slack_workspace_one))
  end

  test "a reading is not started, running, done or failed with the jobs it lists, and a state it does not know moves nothing" do
    stub_model(content: { state: "done", said: "web runs the new version.", parts: [] })
    assert_equal [ "done", "web runs the new version." ],
                 reading_of(@judge.reading(question: "web is live", readings: [ [ Time.current, "web is live" ] ], so_far: "not started"))

    stub_model(content: { state: "running", said: "The release run is going.",
                          parts: [ { name: "tag", state: "passed" }, { name: "trigger-northflank", state: "running" }, { name: "", state: "passed" },
                                   { name: "build", state: "maybe" } ] })
    reading = @judge.reading(question: "the release finishes", readings: [ [ 2.minutes.ago, "queued" ], [ Time.current, "in_progress" ] ], so_far: "not started")
    assert_equal FirefightAi::Schemas::WatchReading::RUNNING, reading.state
    assert_equal [ %w[tag passed], %w[trigger-northflank running] ], reading.parts

    stub_model(content: { state: "maybe", said: "" })
    assert_nil @judge.reading(question: "web is live", readings: [ [ nil, "a" ], [ Time.current, "b" ] ], so_far: "running").state
  end

  test "every recent reading is put to the model, oldest first, the newest with the most room" do
    stub_model(content: { state: "running", said: "build-images running, 4 of 7 jobs done.", parts: [] })
    chat = RubyLLM.chat
    asked = nil
    chat.expects(:ask).with { |text| asked = text }.returns(llm_reply(content: { state: "running", said: "x", parts: [] }, input: 10, output: 5, cost: 0.0))
    long = "#{'node ok. ' * 1_000}node deploy-web failed"
    @judge.reading(question: "the release finishes", readings: [ [ 3.minutes.ago, "queued" ], [ Time.current, long ] ], so_far: "running")

    assert_operator asked.index("Reading 1 of 2"), :<, asked.index("Reading 2 of 2, the newest")
    assert_includes asked, "queued"
    assert_includes asked, "node ok."
  end

  test "a good end is said as where it leaves the goal, with nothing offered" do
    stub_model(content: "web is serving 7676c83.")
    assert_equal "web is serving 7676c83.", @judge.standing(purpose: "ship main", happened: "Release done in 7 minutes.", offer: false)
    assert_no_match(/shall I|\?/, FirefightAi::WatchJudge::SETTLED_PROMPT.lines.first)
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
