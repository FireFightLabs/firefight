require "test_helper"

class FirefightAi::PermissionJudgeTest < ActiveSupport::TestCase
  setup do
    @judge = FirefightAi::PermissionJudge.new(workspaces(:slack_workspace_one))
  end

  test "Halon lets the agent go on, stops it, or leaves it to the person, always with why" do
    stub_model(content: { decision: "allow", reason: "It reruns the test after each edit, so it is making progress." })
    assert_equal FirefightAi::PermissionJudge::Decision.new(decision: "allow", reason: "It reruns the test after each edit, so it is making progress.", lean: nil),
                 @judge.decide(asked: "Run bundle exec rspec a fourth time", steps: [ "Ran bundle exec rspec", "Edited app.rb" ], known: "", can_ask: true)

    stub_model(content: { decision: "ask", lean: "allow", reason: "It could be waiting on a slow service, which the person knows." })
    assert_equal [ "ask", "allow" ], @judge.decide(asked: "Run curl again", steps: [], known: "", can_ask: true).then { |decided| [ decided.decision, decided.lean ] }
  end

  test "asking the person without a way to lean is an error, since nobody answering in time goes with the lean" do
    stub_model(content: { decision: "ask", lean: "", reason: "Unsure." })
    assert_raises(FirefightAi::TerminalError) { @judge.decide(asked: "x", steps: [], known: "", can_ask: true) }
  end

  test "with nobody to ask Halon must choose, and is handed a schema without ask" do
    schema = nil
    stub_model(content: { decision: "stop", reason: "It ran the same command three times with the same result." }, schema: ->(given) { schema = given })

    assert_equal "stop", @judge.decide(asked: "Run ls again", steps: [ "Ran ls", "Ran ls", "Ran ls" ], known: "", can_ask: false).decision
    assert_equal FirefightAi::Schemas::PermissionDecisionAlone, schema
  end

  test "an answer without a decision it may give, or without a reason, is an error rather than a guess" do
    stub_model(content: { decision: "ask", reason: "Unsure." })
    assert_raises(FirefightAi::TerminalError) { @judge.decide(asked: "x", steps: [], known: "", can_ask: false) }

    stub_model(content: { decision: "allow", reason: "" })
    assert_raises(FirefightAi::TerminalError) { @judge.decide(asked: "x", steps: [], known: "", can_ask: true) }
  end

  test "Halon is taught to judge a loop by what changed between the repeats, not by a rule against repeating" do
    instructions = nil
    stub_model(content: { decision: "allow", reason: "Progress." }, instructions: ->(text) { instructions = text })
    @judge.decide(asked: "x", steps: [], known: "", can_ask: true)

    assert_includes instructions, "Look at what changed between the repeats"
    assert_includes instructions, "runs a test, edits the code, and runs the test again"
    assert_includes instructions, "waiting again for an answer it asked for"
    assert_includes instructions, FirefightAi::Copy::PEOPLE
  end

  private

  def stub_model(content:, instructions: nil, schema: nil)
    chat = mock("chat")
    chat.stubs(:with_max_output_tokens).returns(chat)
    if instructions
      chat.stubs(:with_instructions).with { |text| instructions.call(text) }.returns(chat)
    else
      chat.stubs(:with_instructions).returns(chat)
    end
    if schema
      chat.stubs(:with_schema).with { |given| schema.call(given) }.returns(chat)
    else
      chat.stubs(:with_schema).returns(chat)
    end
    reply = llm_reply(content: content, input: 100, output: 20, cost: 0.0001)
    reply.stubs(:parsed).returns(content.deep_stringify_keys)
    chat.stubs(:ask).returns(reply)
    RubyLLM.stubs(:chat).returns(chat)
  end
end
