require "test_helper"

# A replay runs Halon's reasoning aids as a live chat does: the suspects told before its first call, read from the
# scenario's own what changed, the theory board, and the challenger's second look at a cause it confirms.
class Conversation::RehearsalReasoningTest < ActiveSupport::TestCase
  CHANGES = "13:38 worker deploy d-412 by Sam Rivera https://app.northflank.com/t/larkspur/project/shop/services/worker/deployments/d-412".freeze

  setup do
    workspace = workspaces(:slack_workspace_one)
    run = Conversation::BenchRun.create!(kind: Conversation::BenchRun::KIND_SCENARIOS, trigger: Conversation::BenchRun::TRIGGER_TERMINAL,
                                         prompt_version: "test", model: "gpt-4o")
    @result = run.results.create!(workspace: workspace, scenario: "pool", title: "Pool")
    @model = FirefightAi::ModelChoice.new(model: "gpt-4o")
    RubyLLM.config.stubs(:openai_api_key).returns("sk-test")
    FirefightAi.stubs(:tool_search?).returns(false)
    FirefightAi.configuration.stubs(:held_tools_budget).returns(1_000_000)
    @offered = []
  end

  test "the suspects are told before the first call, the board is in hand, and a confirmed cause the challenger doubts goes back once" do
    FirefightAi::Challenger.any_instance.expects(:challenge).once.returns(
      FirefightAi::Challenger::Verdict.new(verdict: FirefightAi::Schemas::Challenge::CONTRADICTED, reason: "orders was full before 13:38.", checks: [])
    )
    script(
      call("update_theories", "theories" => [ { "title" => "worker's deploy raised its pool", "status" => "confirmed", "evidence" => "what changed", "leading" => true } ]),
      reply("It was worker's deploy."),
      reply("Having looked again, it was still worker's deploy, since orders filled at 13:38.")
    )

    replay = Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)
    nudges = replay.chat.messages.where(nudge: true).map(&:content)

    assert nudges.first.start_with?(ResourceMap::Suspects::LEAD_WORDS)
    assert_includes nudges.first, "deployments/d-412"
    assert_includes @offered.first, :update_theories
    assert_match "orders was full before 13:38.", nudges.second
    assert_equal 3, @offered.size, "sent back once, then the turn ends"
    assert_includes replay.transcript.to_text, "Agent updated its Theory board:"
  end

  private

  def bench_case
    Conversation::BenchCase.from_hash({
      "title" => "Pool", "context" => "You are acting for Sam.", "turns" => [ "api is erroring, why?" ],
      "tools" => [ { "name" => "open_tools", "description" => "Opens groups", "base" => true },
                   { "name" => "search_logs", "description" => "Searches logs", "reads" => true },
                   { "name" => "what_changed", "description" => "What changed", "reads" => true } ],
      "answers" => [ { "tool" => "what_changed", "result" => CHANGES } ]
    }, key: "pool")
  end

  def call(name, arguments)
    id = "call_#{SecureRandom.hex(4)}"
    llm_reply(content: "", tool_calls: { id => RubyLLM::ToolCall.new(id: id, name: name, arguments: arguments) }, finish_reason: :tool_calls)
  end

  def reply(text) = llm_reply(content: text)

  def script(*replies)
    first, *rest = replies
    stubbed = RubyLLM::Provider.any_instance.stubs(:complete).with { |_messages, tools:, **| @offered << tools.keys }.returns(first)
    rest.each { |each| stubbed = stubbed.then.returns(each) }
  end
end
