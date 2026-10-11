require "test_helper"

# The bench replays a scenario the way the deployment runs Halon, so the same code is measured both ways: with
# specialists off Halon reads a connected system itself, and on it asks the specialist for that kind, which reads the
# scenario's world, only reads, and reports with the lines and links Halon cites.
class Conversation::RehearsalSpecialistsTest < ActiveSupport::TestCase
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
    @offered = []
  end

  test "with specialists off Halon reads the connected system itself, as today" do
    script(call("planetscale_get_insights", "database" => "orders"), reply("orders is at 498 of 500 connections."))

    replay = Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)

    assert_equal [ "planetscale_get_insights" ], replay.transcript.calls.map(&:name)
    assert_includes @offered.first, :planetscale_get_insights
    assert_not_includes @offered.first, :ask_specialist
  end

  test "with specialists on Halon asks the databases specialist, which reads the world, reports its lines and links, and never writes" do
    FirefightAi.configuration.stubs(:specialists).returns(true)
    script(
      call("ask_specialist", "asks" => [ { "domain" => "databases", "objective" => "Who holds orders' connections?" } ]),
      call("planetscale_api_request", "method" => "POST", "path" => "/branches"),
      call("planetscale_get_insights", "database" => "orders"),
      call("report_findings", "summary" => "orders is out of connections", "findings" => [
        { "claim" => "orders is at its limit", "lines" => [ "open connections 498 of 500 since 13:39" ],
          "links" => [ "https://app.planetscale.com/larkspur/orders/main/insights" ] }
      ]),
      reply("orders is at 498 of 500 connections, see https://app.planetscale.com/larkspur/orders/main/insights")
    )

    replay = Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)
    halon, specialist = @offered

    assert_includes halon, :ask_specialist
    assert_not_includes halon, :planetscale_get_insights, "a connection's read is the specialist's"
    assert_includes specialist, :planetscale_get_insights
    assert_includes specialist, :report_findings
    assert_not_includes specialist, :open_tools

    calls = replay.transcript.calls
    assert_equal %w[ask_specialist planetscale_api_request planetscale_get_insights], calls.map(&:name)
    asked, refused, read = calls
    assert_equal [ nil, "databases", "databases" ], calls.map(&:by)
    assert_equal Conversation::Rehearsal::Specialists::ONLY_READS, refused.result, "a specialist never makes a change"
    assert_equal INSIGHTS, read.result
    assert_includes asked.result, "Shows: open connections 498 of 500 since 13:39"
    assert_includes asked.result, "Link: https://app.planetscale.com/larkspur/orders/main/insights"
    assert_includes replay.transcript.to_text, "The databases specialist, for the agent, called planetscale_get_insights"
    assert replay.transcript.cites_any?([ "orders/main/insights" ])
  end

  test "the two ways have different prompt versions, so a bench run says which it measured" do
    off = Conversation::Bench.send(:prompt_version, @result.workspace, @model)
    FirefightAi.configuration.stubs(:specialists).returns(true)

    assert_not_equal off, Conversation::Bench.send(:prompt_version, @result.workspace, @model)
  end

  private

  def bench_case
    Conversation::BenchCase.from_hash({
      "title" => "Connections", "context" => "You are acting for Sam, whose role in this workspace is admin.", "turns" => [ "why is orders refusing connections?" ],
      "tools" => [
        { "name" => "open_tools", "description" => "Opens groups", "base" => true },
        { "name" => "planetscale_get_insights", "description" => "Query insights for a branch", "reads" => true, "source" => "planetscale",
          "parameters" => { "type" => "object", "properties" => { "database" => { "type" => "string" } } } },
        { "name" => "planetscale_api_request", "description" => "Call the PlanetScale API", "confirms" => true, "source" => "planetscale",
          "reads_when" => { "method" => [ "GET" ] },
          "parameters" => { "type" => "object", "properties" => { "method" => { "type" => "string" }, "path" => { "type" => "string" } } } }
      ],
      "answers" => [ { "tool" => "planetscale_get_insights", "result" => INSIGHTS } ]
    }, key: "connections")
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
