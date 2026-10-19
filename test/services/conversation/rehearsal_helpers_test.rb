require "test_helper"

# A replay offers run_helpers as a live chat does, and a call to it runs real helpers on the scenario's own reads, so the
# bench measures what helpers do and what they cost rather than a report someone wrote.
class Conversation::RehearsalHelpersTest < ActiveSupport::TestCase
  INSIGHTS = "orders/main: open connections 498 of 500 since 13:39. https://app.planetscale.com/larkspur/orders/main/insights".freeze

  setup do
    workspace = workspaces(:slack_workspace_one)
    run = Conversation::BenchRun.create!(kind: Conversation::BenchRun::KIND_SCENARIOS, trigger: Conversation::BenchRun::TRIGGER_TERMINAL,
                                         prompt_version: "test", model: "gpt-4o")
    @result = run.results.create!(workspace: workspace, scenario: "connections", title: "Connections")
    @model = FirefightAi::ModelChoice.new(model: "gpt-4o")
    # Every reply below is scripted, so the key is never sent anywhere.
    RubyLLM.config.stubs(:openai_api_key).returns("sk-test")
    FirefightAi.stubs(:tool_search?).returns(false)
    FirefightAi.configuration.stubs(:held_tools_budget).returns(1_000_000)
    FirefightAi.configuration.stubs(:specialists).returns(:off)
    @offered = []
  end

  test "run_helpers runs a real helper on the scenario's reads, which never changes anything, and what it spends is Halon's" do
    script(
      call("run_helpers", "checks" => [ { "title" => "Insights of orders", "brief" => "Read orders' insights and say who holds the connections" } ]),
      call("planetscale_api_request", "method" => "POST", "path" => "/branches"),
      call("planetscale_get_insights", "database" => "orders"),
      reply("orders is at 498 of 500 connections since 13:39.", cost: 0.02),
      reply("orders is at 498 of 500 connections, see https://app.planetscale.com/larkspur/orders/main/insights", cost: 0.01)
    )

    replay = Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)
    halon, helper = @offered

    assert_includes halon, :run_helpers
    assert_includes helper, :planetscale_get_insights
    assert_includes helper, :read_result
    assert_not_includes helper, :run_helpers
    assert_not_includes helper, :open_tools

    calls = replay.transcript.calls
    assert_equal %w[run_helpers planetscale_api_request planetscale_get_insights], calls.map(&:name)
    asked, refused, read = calls
    assert_equal [ nil, "A helper", "A helper" ], calls.map(&:by)
    assert_equal Conversation::Rehearsal::Helpers::ONLY_READS, refused.result
    assert_equal INSIGHTS, read.result
    assert_includes asked.result, "- Insights of orders (helper_1): orders is at 498 of 500 connections since 13:39."
    assert_includes replay.transcript.to_text, "A helper, for the agent, called planetscale_get_insights"
    assert_equal 30_000, Conversation::Bench.send(:spent, @result), "the helper's call counts as Halon's cost"
  end

  test "with helpers turned off a replay offers no run_helpers, and the run's prompt version says so" do
    FirefightAi.configuration.stubs(:helpers?).returns(false)
    script(reply("I need to read orders' insights first."))

    Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)

    assert_not_includes @offered.first, :run_helpers
    assert Conversation::Bench.send(:prompt_version, @result.workspace, @model).end_with?(Conversation::Bench::WITHOUT_HELPERS)
  end

  private

  def bench_case
    Conversation::BenchCase.from_hash({
      "title" => "Connections", "context" => "You are acting for Sam, whose role in this workspace is admin.",
      "turns" => [ "why is orders refusing connections?" ],
      "tools" => [
        { "name" => "planetscale_get_insights", "description" => "Query insights for a branch", "reads" => true, "source" => "planetscale",
          "parameters" => { "type" => "object", "properties" => { "database" => { "type" => "string" } } } },
        { "name" => "planetscale_api_request", "description" => "Call the PlanetScale API", "confirms" => true, "source" => "planetscale",
          "reads_when" => { "method" => [ "GET" ] },
          "parameters" => { "type" => "object", "properties" => { "method" => { "type" => "string" }, "path" => { "type" => "string" } } } }
      ],
      "answers" => [ { "tool" => "planetscale_get_insights", "result" => INSIGHTS },
                     { "tool" => "planetscale_api_request", "match" => { "method" => "POST" }, "result" => "Created branch raise-limit." } ]
    }, key: "connections")
  end

  def call(name, arguments)
    id = "call_#{SecureRandom.hex(4)}"
    llm_reply(content: "", tool_calls: { id => RubyLLM::ToolCall.new(id: id, name: name, arguments: arguments) }, finish_reason: :tool_calls)
  end

  def reply(text, cost: 0.0) = llm_reply(content: text, cost: cost)

  def script(*replies)
    first, *rest = replies
    stubbed = RubyLLM::Provider.any_instance.stubs(:complete).with { |_messages, tools:, **| @offered << tools.keys }.returns(first)
    rest.each { |each| stubbed = stubbed.then.returns(each) }
  end
end
